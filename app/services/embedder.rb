require "net/http"
require "json"

class Embedder
  BASE        = "https://generativelanguage.googleapis.com/v1beta"
  MODEL       = ENV.fetch("GEMINI_EMBED_MODEL", "gemini-embedding-001")
  DIMS        = 1536
  BATCH       = ENV.fetch("GEMINI_EMBED_BATCH", "25").to_i
  MAX_RPM     = ENV.fetch("GEMINI_EMBED_RPM", "100").to_i
  MAX_TPM     = ENV.fetch("GEMINI_EMBED_TPM", "30000").to_i
  SAFE_TPM    = (MAX_TPM * 0.85).to_i
  WINDOW_SECS = 61.0
  MAX_RETRIES = 5

  @mutex  = Mutex.new
  @window = []

  # Chunks do documento (indexação)
  def self.call(texts, task: "RETRIEVAL_DOCUMENT")
    build_batches(Array(texts)).flat_map do |batch|
      tokens = batch.sum { |t| estimate_tokens(t) }
      wait_for_quota(requests: batch.size, tokens: tokens)
      request(batch, task)
    end
  end

  # Pergunta do usuário (consulta)
  def self.one(text) = call([text], task: "RETRIEVAL_QUERY").first

  # Estimativa conservadora (~3 chars/token em português) para não estourar TPM.
  def self.estimate_tokens(text)
    [(text.to_s.length / 3.0).ceil, 1].max
  end

  # Agrupa textos respeitando o limite de itens (BATCH/MAX_RPM) e de tokens (SAFE_TPM).
  def self.build_batches(texts)
    batches = []
    current = []
    current_tokens = 0
    max_items = [BATCH, MAX_RPM].min

    texts.each do |text|
      t_tokens = estimate_tokens(text)
      if current.any? && (current.size >= max_items || current_tokens + t_tokens > SAFE_TPM)
        batches << current
        current = []
        current_tokens = 0
      end
      current << text
      current_tokens += t_tokens
    end
    batches << current if current.any?
    batches
  end

  # Janela deslizante de 60s para respeitar RPM e TPM do plano antes de disparar a requisição.
  def self.wait_for_quota(requests:, tokens:)
    loop do
      sleep_time = @mutex.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @window.reject! { |entry| now - entry[:at] >= WINDOW_SECS }

        used_reqs   = @window.sum { |e| e[:requests] }
        used_tokens = @window.sum { |e| e[:tokens] }

        if @window.empty? || (used_reqs + requests <= MAX_RPM && used_tokens + tokens <= SAFE_TPM)
          @window << { at: now, requests: requests, tokens: tokens }
          0
        else
          oldest = @window.first[:at]
          [(oldest + WINDOW_SECS) - now, 1.0].max
        end
      end

      break if sleep_time <= 0

      Rails.logger.info("[Embedder] Aguardando #{sleep_time.ceil}s para respeitar limite de cota (RPM=#{MAX_RPM}, TPM=#{MAX_TPM})")
      sleep(sleep_time)
    end
  end

  def self.request(batch, task)
    uri = URI("#{BASE}/models/#{MODEL}:batchEmbedContents")
    body = {
      requests: batch.map do |t|
        { model: "models/#{MODEL}", content: { parts: [{ text: t }] },
          taskType: task, outputDimensionality: DIMS }
      end
    }.to_json

    attempts = 0
    loop do
      attempts += 1
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 120
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json",
                                     "x-goog-api-key" => ENV.fetch("GEMINI_API_KEY"))
      req.body = body

      res = http.request(req)
      if res.is_a?(Net::HTTPSuccess)
        return JSON.parse(res.body)["embeddings"].map { |e| normalize(e["values"]) }
      end

      code = res.code.to_i
      if (code == 429 || code == 503) && attempts <= MAX_RETRIES && !daily_quota_exhausted?(res.body)
        delay = retry_delay_from(res, attempts)
        Rails.logger.warn("[Embedder] HTTP #{code} (tentativa #{attempts}/#{MAX_RETRIES}). Aguardando #{delay.ceil}s...")
        sleep(delay)
        next
      end

      raise "Gemini embed falhou (#{res.code}): #{res.body}"
    end
  end

  def self.daily_quota_exhausted?(body)
    body.to_s.match?(/PerDay|daily/i)
  end

  def self.retry_delay_from(res, attempt)
    if (header = res["Retry-After"]).present? && header.to_f > 0
      return header.to_f + 1.0
    end

    parsed = JSON.parse(res.body) rescue nil
    details = parsed&.dig("error", "details")
    if details.is_a?(Array)
      retry_info = details.find { |d| d["retryDelay"].present? }
      if retry_info && retry_info["retryDelay"].to_s =~ /(\d+(?:\.\d+)?)s/
        return ::Regexp.last_match(1).to_f + 1.0
      end
    end

    [15 * (2**(attempt - 1)), 65].min.to_f
  end

  # Vetores truncados (< 3072 dims) não vêm normalizados.
  def self.normalize(v)
    norm = Math.sqrt(v.sum { |x| x * x })
    norm.zero? ? v : v.map { |x| x / norm }
  end
end
