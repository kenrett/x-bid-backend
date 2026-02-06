class CreateUploadAuthorizations < ActiveRecord::Migration[8.0]
  def change
    create_table :upload_authorizations do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs, on_delete: :cascade }, index: { unique: true }

      t.timestamps
    end
  end
end
