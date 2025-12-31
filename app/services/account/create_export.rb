module Account
  class CreateExport
    def initialize(user:, environment:)
      @user = user
      @environment = environment
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user

      export = AccountExport.create!(user: @user, status: :pending, requested_at: Time.current)
      maybe_generate_sync(export)

      ServiceResult.ok(code: :accepted, data: { export_payload: export_payload(export) })
    rescue StandardError => e
      AppLogger.error(event: "account.export.create_failed", error: e, user_id: @user&.id)
      ServiceResult.fail("Unable to create export", code: :unexpected_error)
    end

    private

    def maybe_generate_sync(export)
      return if @environment.production?

      export.update!(
        status: :ready,
        ready_at: Time.current,
        payload: build_payload
      )
    rescue StandardError => e
      export.update!(status: :failed, error_message: e.message)
    end

    def export_payload(export)
      payload = {
        id: export.id,
        status: export.status,
        requested_at: export.requested_at.iso8601,
        ready_at: export.ready_at&.iso8601,
        download_url: export.download_url
      }
      payload[:data] = export.payload if export.ready? && export.download_url.blank?
      payload
    end

    def build_payload
      {
        user: {
          id: @user.id,
          name: @user.name,
          email_address: @user.email_address,
          email_verified_at: @user.email_verified_at&.iso8601,
          created_at: @user.created_at.iso8601,
          role: @user.role
        },
        purchases: @user.purchases.order(created_at: :desc).limit(100).map do |purchase|
          {
            id: purchase.id,
            amount_cents: purchase.amount_cents,
            currency: purchase.currency,
            status: purchase.status,
            created_at: purchase.created_at.iso8601
          }
        end,
        bids_count: @user.bids.count,
        auction_watches_count: @user.auction_watches.count,
        notifications_count: @user.notifications.count
      }
    end
  end
end
