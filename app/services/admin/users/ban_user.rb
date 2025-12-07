module Admin
  module Users
    # Backwards compatibility wrapper for legacy callers; prefer Admin::Users::Disable.
    class BanUser < Disable
      def initialize(actor:, user:, request: nil)
        super(actor: actor, user: user, request: request)
      end
    end
  end
end
