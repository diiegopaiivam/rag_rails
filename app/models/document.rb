class Document < ApplicationRecord
  has_one_attached :file
  has_many :chunks, dependent: :destroy

  enum :status, { pending: "pending", processing: "processing",
                  ready: "ready", failed: "failed" }, default: "pending"
end
