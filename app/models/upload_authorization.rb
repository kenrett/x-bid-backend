class UploadAuthorization < ApplicationRecord
  belongs_to :user
  belongs_to :blob, class_name: "ActiveStorage::Blob"

  validates :blob_id, uniqueness: true
end
