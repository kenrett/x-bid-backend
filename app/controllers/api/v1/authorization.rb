module Authorization
  extend ActiveSupport::Concern

  included do
    def authorize_admin!
      return if @current_user&.admin?

      render json: { error: "Not authorized" }, status: :forbidden
    end
  end
end