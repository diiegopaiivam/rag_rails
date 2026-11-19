require "pdf/reader"
require "open3"
require "tempfile"

# Retorna [{ page: 1, text: "..." }, ...]
# Se o PDF não tem texto (escaneado), tenta OCR com ocrmypdf.
class PdfTextExtractor
  MIN_CHARS_PER_PAGE = 30

  def self.call(path)
    pages = read(path)
    return pages unless needs_ocr?(pages)

    ocr_path = run_ocr(path)
    read(ocr_path)
  end

  def self.read(path)
    PDF::Reader.new(path).pages.map.with_index(1) do |p, i|
      { page: i, text: p.text.to_s.gsub(/[ \t]+/, " ").strip }
    end
  end

  def self.needs_ocr?(pages)
    return true if pages.empty?
    avg = pages.sum { |p| p[:text].length } / pages.size.to_f
    avg < MIN_CHARS_PER_PAGE
  end

  def self.run_ocr(path)
    out = Tempfile.new(["ocr", ".pdf"]).path
    _o, err, st = Open3.capture3("ocrmypdf", "--force-ocr", "-l", "por+eng", path, out)
    raise "OCR falhou: #{err}" unless st.success?
    out
  end
end
