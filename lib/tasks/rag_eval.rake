require "yaml"

# Uso: bin/rails rag:eval DOCUMENT_ID=1
# Opcionais: GOLDEN=eval/golden.yml  SLEEP=1 (segundos entre perguntas, p/ limite de cota)
namespace :rag do
  desc "Avalia o RAG contra o golden set"
  task eval: :environment do
    norm = ->(s) { I18n.transliterate(s.to_s.downcase) }

    doc     = Document.find(ENV.fetch("DOCUMENT_ID"))
    cases   = YAML.load_file(ENV.fetch("GOLDEN", Rails.root.join("eval/golden.yml")))
    rag     = RagAnswerer.new(doc)
    results = []

    cases.each_with_index do |c, i|
      res       = rag.call(c["question"])
      answer    = res[:answer].to_s
      retrieved = res[:sources].map { |s| s[:page] }.uniq
      refused   = norm.(answer).include?("nao encontrei")
      cited     = answer.scan(/\[p\.?\s*([\d,\s]+)\]/).flatten
                        .flat_map { |s| s.split(",").map(&:to_i) }.uniq

      if c["should_refuse"]
        hit, ok = nil, refused
      else
        hit = (Array(c["expected_pages"]) & retrieved).any?
        ok  = !refused && Array(c["must_include"]).all? { |t| norm.(answer).include?(norm.(t)) }
      end
      # citação válida: só cita páginas que realmente foram recuperadas
      cite_ok = refused || (cited.any? && (cited - retrieved).empty?)

      results << { q: c["question"], refuse_case: c["should_refuse"], hit: hit, ok: ok,
                   cite_ok: cite_ok, retrieved: retrieved, expected: c["expected_pages"], answer: answer }

      status = ok ? "OK  " : "FALHA"
      puts "#{status} [#{i + 1}/#{cases.size}] #{c['question']}"
      sleep ENV["SLEEP"].to_f if ENV["SLEEP"]
    end

    factual = results.reject { |r| r[:refuse_case] }
    refusal = results.select { |r| r[:refuse_case] }
    pct = ->(n, d) { d.zero? ? "n/a" : "#{(100.0 * n / d).round}% (#{n}/#{d})" }

    puts "\n=== Resumo ==="
    puts "Recuperação (página certa no top-k): #{pct.(factual.count { |r| r[:hit] }, factual.size)}"
    puts "Resposta correta:                    #{pct.(factual.count { |r| r[:ok] }, factual.size)}"
    puts "Recusa correta (fora do escopo):     #{pct.(refusal.count { |r| r[:ok] }, refusal.size)}"
    puts "Citações válidas:                    #{pct.(results.count { |r| r[:cite_ok] }, results.size)}"

    failures = results.reject { |r| r[:ok] }
    unless failures.empty?
      puts "\n=== Falhas ==="
      failures.each do |r|
        kind = if r[:refuse_case] then "ALUCINAÇÃO (deveria recusar)"
               elsif !r[:hit]      then "RECUPERAÇÃO (página certa não veio)"
               else                     "GERAÇÃO (trecho veio, resposta errada)" end
        puts "\n- #{r[:q]}\n  tipo: #{kind}\n  esperado: #{r[:expected].inspect} | recuperado: #{r[:retrieved].inspect}"
        puts "  resposta: #{r[:answer].truncate(300)}"
      end
    end
  end
end
