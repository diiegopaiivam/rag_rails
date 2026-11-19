require "net/http"
require "json"

class LlmClient
  BASE        = "https://generativelanguage.googleapis.com/v1beta"
  MODEL       = ENV.fetch("GEMINI_LLM_MODEL", "gemini-2.5-flash")
  MAX_TOKENS  = ENV.fetch("GEMINI_MAX_OUTPUT_TOKENS", "4096").to_i
  MAX_RETRIES = 3

  # max_tokens maior: em modelos com "thinking", os tokens de raciocínio
  # contam no limite e podem cortar a resposta.
  def self.call(system:, user:, max_tokens: MAX_TOKENS)
    uri = URI("#{BASE}/models/#{MODEL}:generateContent")
    body = {
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: "user", parts: [{ text: user }] }],
      generationConfig: { maxOutputTokens: max_tokens, temperature: 0.1 }
    }.to_json

    attempts = 0
    res = loop do
      attempts += 1
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 120
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json",
                                     "x-goog-api-key" => ENV.fetch("GEMINI_API_KEY"))
      req.body = body

      response = http.request(req)
      break response if response.is_a?(Net::HTTPSuccess)

      code = response.code.to_i
      if (code == 429 || code == 503) && attempts <= MAX_RETRIES && !Embedder.daily_quota_exhausted?(response.body)
        delay = Embedder.retry_delay_from(response, attempts)
        Rails.logger.warn("[LlmClient] HTTP #{code} (tentativa #{attempts}/#{MAX_RETRIES}). Aguardando #{delay.ceil}s...")
        sleep(delay)
        next
      end

      raise "Gemini falhou (#{response.code}): #{response.body}"
    end

    parts = JSON.parse(res.body).dig("candidates", 0, "content", "parts") || []
    text = parts.filter_map { |p| p["text"] }.join("\n")
    raise "Resposta vazia do Gemini: #{res.body.truncate(300)}" if text.blank?

    text
  end
end