Subindo o RAG com Docker (Rails + Postgres/pgvector + Redis + Sidekiq)

1. Copiar os arquivos
Dockerfile, docker-compose.yml, .dockerignore e .env.example (esta pasta) para a raiz
Gemini: gemini/embedder.rb e gemini/llm_client.rb sobre app/services/
Avaliação: eval/golden.yml e lib/tasks/rag_eval.rake

2. Configurar e subir
cp .env.example .env              # preencha GEMINI_API_KEY ou qualquer outro LLM
docker compose build
docker compose run --rm web bin/rails active_storage:install
docker compose up -d
docker compose exec -it web bundle exec rails db:migrate

4. Testar
curl localhost:3000/up
curl -F "file=@manual.pdf" localhost:3000/api/v1/documents
curl localhost:3000/api/v1/documents/1          # espere "status": "ready"
curl -X POST localhost:3000/api/v1/documents/1/ask \
     -H "Content-Type: application/json" \
     -d '{"question": "Qual a pressão recomendada dos pneus?"}'

5. Avaliar
docker compose exec web bin/rails rag:eval DOCUMENT_ID=1 SLEEP=1