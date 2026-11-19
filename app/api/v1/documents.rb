module V1
  class Documents < Grape::API
    version "v1", using: :path
    format :json
    prefix :api

    MAX_SIZE = 50.megabytes

    resource :documents do
      desc "Envia um PDF para indexação"
      params { requires :file, type: File }
      post do
        f = params[:file]
        error!({ error: "Envie um arquivo PDF" }, 422) unless f[:type] == "application/pdf"
        error!({ error: "Arquivo muito grande" }, 413) if f[:tempfile].size > MAX_SIZE

        doc = Document.create!(title: f[:filename])
        doc.file.attach(io: f[:tempfile], filename: f[:filename], content_type: "application/pdf")
        IngestDocumentJob.perform_async(doc.id)
        { id: doc.id, status: doc.status }
      end

      route_param :id do
        desc "Status da indexação"
        get do
          doc = Document.find(params[:id])
          { id: doc.id, title: doc.title, status: doc.status,
            pages: doc.pages_count, chunks: doc.chunks.count, error: doc.error_message }
        end

        desc "Pergunta sobre o PDF"
        params { requires :question, type: String }
        post :ask do
          doc = Document.find(params[:id])
          error!({ error: "Documento ainda não está pronto (#{doc.status})" }, 409) unless doc.ready?
          RagAnswerer.new(doc).call(params[:question])
        end
      end
    end
  end
end
