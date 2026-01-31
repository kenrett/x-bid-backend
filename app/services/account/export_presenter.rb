module Account
  class ExportPresenter
    def initialize(export:)
      @export = export
    end

    def payload
      {
        id: export.id,
        status: export.status,
        requested_at: export.requested_at.iso8601,
        ready_at: export.ready_at&.iso8601,
        download_url: download_url
      }
    end

    private

    attr_reader :export

    def download_url
      return export.download_url if export.download_url.present?
      return nil unless export.ready?

      Account::ExportUrlSigner.new.signed_url_for(export)
    end
  end
end
