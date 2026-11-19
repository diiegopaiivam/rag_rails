class CreateDocumentsAndChunks < ActiveRecord::Migration[7.1]
  def change
    create_table :documents do |t|
      t.string  :title
      t.string  :status, null: false, default: "pending" # pending/processing/ready/failed
      t.integer :pages_count
      t.text    :error_message
      t.timestamps
    end

    create_table :chunks do |t|
      t.references :document, null: false, foreign_key: true
      t.text    :content, null: false
      t.integer :page
      t.integer :position
      t.vector  :embedding, limit: 1536 # text-embedding-3-small
      t.timestamps
    end

    add_index :chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
