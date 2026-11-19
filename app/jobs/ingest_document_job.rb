class IngestDocumentJob
  include Sidekiq::Job
  sidekiq_options retry: 2

  def perform(document_id)
    doc = Document.find(document_id)
    doc.update!(status: "processing", error_message: nil)

    doc.file.open do |tmp|
      pages  = PdfTextExtractor.call(tmp.path)
      chunks = Chunker.call(pages)
      raise "Nenhum texto extraído do PDF" if chunks.empty?

      vectors = Embedder.call(chunks.map { |c| c[:content] })

      Document.transaction do
        doc.chunks.delete_all
        rows = chunks.each_with_index.map do |c, i|
          c.merge(document_id: doc.id, embedding: vectors[i],
                  created_at: Time.current, updated_at: Time.current)
        end
        Chunk.insert_all!(rows)
        doc.update!(status: "ready", pages_count: pages.size)
      end
    end
  rescue => e
    doc&.update(status: "failed", error_message: e.message.truncate(500))
    raise
  end
end
