class Current < ActiveSupport::CurrentAttributes
  attribute :request_id, :user_id, :session_token_id, :ip_address, :user_agent, :storefront_key
end
