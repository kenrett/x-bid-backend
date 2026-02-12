module OasSchemasRuntime
  STATUSES = %w[inactive scheduled active complete cancelled].freeze
  BID_PACK_STATUSES = %w[active retired].freeze
  PURCHASE_STATUSES = %w[
    created
    paid_pending_apply
    applied
    failed
    partially_refunded
    refunded
    voided
  ].freeze

  SCHEMAS = {
    "Auction" => {
      type: "object",
      description: "Full auction details including pricing and winner information.",
      properties: {
        id: { type: "integer" },
        title: { type: "string" },
        description: { type: "string" },
        status: { type: "string", enum: STATUSES },
        start_date: { type: "string", format: "date-time" },
        end_time: { type: "string", format: "date-time" },
        current_price: { type: "number", format: "float" },
        image_url: {
          type: "string",
          nullable: true,
          description: "Stable upload path (`/api/v1/uploads/:signed_id`) for authorized uploads; legacy external URLs may appear for older records."
        },
        highest_bidder_id: { type: "integer", nullable: true },
        winning_user_id: { type: "integer", nullable: true },
        winning_user_name: { type: "string", nullable: true },
        bids: {
          type: "array",
          nullable: true,
          items: { "$ref" => "#/components/schemas/Bid" }
        }
      },
      required: %w[id title description status start_date end_time current_price]
    },
    "AuctionSummary" => {
      type: "object",
      description: "Slimmer auction representation for list views to reduce payload size.",
      properties: {
        id: { type: "integer" },
        title: { type: "string" },
        status: { type: "string", enum: STATUSES },
        end_time: { type: "string", format: "date-time" },
        current_price: { type: "number", format: "float" },
        image_url: {
          type: "string",
          nullable: true,
          description: "Stable upload path (`/api/v1/uploads/:signed_id`) for authorized uploads; legacy external URLs may appear for older records."
        },
        winning_user_id: { type: "integer", nullable: true },
        winning_user_name: { type: "string", nullable: true }
      },
      required: %w[id title status end_time current_price]
    },
    "Bid" => {
      type: "object",
      description: "A single bid placed against an auction.",
      properties: {
        id: { type: "integer" },
        auction_id: { type: "integer", nullable: true },
        user_id: { type: "integer" },
        username: { type: "string" },
        amount: { type: "number", format: "float" },
        created_at: { type: "string", format: "date-time" }
      },
      required: %w[id user_id username amount created_at]
    },
    "BidHistoryItem" => {
      type: "object",
      description: "Bid history entry with bidder display name.",
      properties: {
        id: { type: "integer" },
        user_id: { type: "integer" },
        username: { type: "string" },
        amount: { type: "number", format: "float" },
        created_at: { type: "string", format: "date-time" }
      },
      required: %w[id user_id username amount created_at]
    },
    "BidHistoryResponse" => {
      type: "object",
      description: "Envelope returned from bid history endpoints.",
      properties: {
        auction: {
          type: "object",
          properties: {
            winning_user_id: { type: "integer", nullable: true },
            winning_user_name: { type: "string", nullable: true }
          }
        },
        bids: {
          type: "array",
          items: { "$ref" => "#/components/schemas/BidHistoryItem" }
        }
      },
      required: %w[auction bids]
    },
    "BidPack" => {
      type: "object",
      description: "Information about a purchasable bid pack.",
      properties: {
        id: { type: "integer" },
        name: { type: "string" },
        bids: { type: "integer", description: "Number of bids included." },
        price: { type: "number", format: "float" },
        pricePerBid: { type: "string" },
        highlight: { type: "boolean", nullable: true },
        description: { type: "string", nullable: true },
        status: { type: "string", enum: BID_PACK_STATUSES },
        active: { type: "boolean" }
      },
      required: %w[id name bids price status active]
    },
    "User" => {
      type: "object",
      description: "Minimal user payload returned by authenticated endpoints.",
      properties: {
        id: { type: "integer" },
        name: { type: "string" },
        role: { type: "string" },
        is_admin: { type: "boolean" },
        is_superuser: { type: "boolean" }
      },
      required: %w[id name role is_admin is_superuser]
    },
    "UserSession" => {
      type: "object",
      description: "Auth Contract v1 session details returned after signup/login/refresh.",
      properties: {
        access_token: { type: "string", description: "JWT used for authenticated requests." },
        refresh_token: { type: "string" },
        session_token_id: {
          oneOf: [
            { type: "integer" },
            { type: "string" }
          ]
        },
        user: { "$ref" => "#/components/schemas/User" }
      },
      required: %w[access_token refresh_token session_token_id user]
    },
    "LoggedInStatus" => {
      type: "object",
      description: "Session validity and context returned by GET /api/v1/logged_in.",
      properties: {
        logged_in: { type: "boolean" },
        user: { "$ref" => "#/components/schemas/User" },
        session_expires_at: { type: "string", format: "date-time", nullable: true }
      },
      required: %w[logged_in user session_expires_at]
    },
    "CheckoutSession" => {
      type: "object",
      description: "Stripe checkout session details used to complete purchases.",
      properties: {
        clientSecret: { type: "string", description: "Client secret used to render the Stripe checkout flow." },
        payment_status: { type: "string", nullable: true },
        status: { type: "string", nullable: true },
        message: { type: "string", nullable: true },
        updated_bid_credits: { type: "integer", nullable: true }
      },
      required: %w[clientSecret]
    },
    "CheckoutStatus" => {
      type: "object",
      description: "Read-only checkout status returned by GET /api/v1/checkout/success.",
      properties: {
        status: { type: "string", enum: %w[pending applied failed] },
        purchase_id: {
          oneOf: [
            { type: "integer" },
            { type: "string" }
          ]
        },
        message: { type: "string", nullable: true }
      },
      required: %w[status purchase_id]
    },
    "Purchase" => {
      type: "object",
      description: "Bid-pack purchase record for the current user.",
      properties: {
        id: { type: "integer" },
        created_at: { type: "string", format: "date-time" },
        status: { type: "string", enum: PURCHASE_STATUSES },
        amount_cents: { type: "integer", minimum: 0 },
        currency: { type: "string" },
        receipt_status: { type: "string", enum: %w[pending available unavailable] },
        receipt_url: { type: "string", format: "uri", nullable: true },
        bid_pack: {
          type: "object",
          properties: {
            id: { type: "integer" },
            name: { type: "string" },
            credits: { type: "integer" },
            price_cents: { type: "integer", minimum: 0 }
          },
          required: %w[id name credits price_cents]
        },
        stripe_checkout_session_id: { type: "string", nullable: true },
        stripe_payment_intent_id: { type: "string", nullable: true }
      },
      required: %w[id created_at status amount_cents currency receipt_status bid_pack]
    },
    "Error" => {
      type: "object",
      description: "Standard error envelope returned by all error responses.",
      properties: {
        error: {
          type: "object",
          properties: {
            code: {
              type: "string",
              description: "Symbol/string code derived from ServiceResult#code so clients can branch on error type.",
              enum: [
                "forbidden",
                "not_found",
                "bad_request",
                "invalid_status",
                "invalid_state",
                "invalid_auction",
                "invalid_bid_pack",
                "invalid_payment",
                "invalid_amount",
                "amount_exceeds_charge",
                "gateway_error",
                "database_error",
                "unexpected_error",
                "validation_error",
                "auction_not_active",
                "insufficient_credits",
                "bid_race_lost",
                "bid_invalid",
                "bid_pack_purchase_failed",
                "invalid_credentials",
                "invalid_session",
                "account_disabled",
                "invalid_token",
                "invalid_password",
                "invalid_email",
                "invalid_user",
                "invalid_delta",
                "already_disabled",
                "already_verified",
                "already_refunded",
                "rate_limited",
                "retired",
                "missing_payment_intent"
              ]
            },
            message: { type: "string" },
            details: {
              oneOf: [
                { type: "object", additionalProperties: true },
                { type: "array", items: {} }
              ],
              nullable: true
            },
            field_errors: {
              type: "object",
              additionalProperties: {
                oneOf: [
                  { type: "array", items: { type: "string" } },
                  { type: "string" }
                ]
              },
              nullable: true
            }
          },
          required: %w[code message]
        }
      },
      required: %w[error]
    },
    "ValidationErrors" => {
      type: "object",
      description: "Validation error payload returned when user input is invalid.",
      properties: {
        errors: {
          type: "array",
          items: { type: "string" }
        }
      },
      required: %w[errors]
    },
    "NotificationPreferences" => {
      type: "object",
      description: "User notification preferences (all boolean flags).",
      additionalProperties: false,
      properties: {
        bidding_alerts: { type: "boolean" },
        outbid_alerts: { type: "boolean" },
        watched_auction_ending: { type: "boolean" },
        receipts: { type: "boolean" },
        product_updates: { type: "boolean" },
        marketing_emails: { type: "boolean" }
      },
      required: %w[bidding_alerts outbid_alerts watched_auction_ending receipts product_updates marketing_emails]
    },
    "AccountProfile" => {
      type: "object",
      additionalProperties: false,
      properties: {
        user: {
          type: "object",
          additionalProperties: false,
          properties: {
            id: { type: "integer" },
            name: { type: "string", nullable: true },
            email_address: { type: "string", format: "email" },
            email_verified: { type: "boolean" },
            email_verified_at: { type: "string", format: "date-time", nullable: true },
            created_at: { type: "string", format: "date-time" },
            notification_preferences: { "$ref" => "#/components/schemas/NotificationPreferences" }
          },
          required: %w[id email_address email_verified created_at notification_preferences]
        }
      },
      required: %w[user]
    },
    "AccountSecurity" => {
      type: "object",
      properties: {
        security: {
          type: "object",
          properties: {
            email_address: { type: "string", format: "email" },
            unverified_email_address: { type: "string", format: "email", nullable: true },
            email_verified: { type: "boolean" },
            email_verified_at: { type: "string", format: "date-time", nullable: true },
            email_verification_sent_at: { type: "string", format: "date-time", nullable: true }
          },
          required: %w[email_address email_verified]
        }
      },
      required: %w[security]
    },
    "NotificationPreferencesResponse" => {
      type: "object",
      properties: {
        notification_preferences: { "$ref" => "#/components/schemas/NotificationPreferences" }
      },
      required: %w[notification_preferences]
    },
    "AccountSession" => {
      type: "object",
      properties: {
        id: { type: "integer" },
        created_at: { type: "string", format: "date-time" },
        last_seen_at: { type: "string", format: "date-time", nullable: true },
        user_agent: { type: "string", nullable: true },
        ip_address: { type: "string", nullable: true },
        current: { type: "boolean" }
      },
      required: %w[id created_at current]
    },
    "AccountSessionsResponse" => {
      type: "object",
      properties: {
        sessions: { type: "array", items: { "$ref" => "#/components/schemas/AccountSession" } }
      },
      required: %w[sessions]
    },
    "AccountExport" => {
      type: "object",
      properties: {
        id: { type: "integer" },
        status: { type: "string", enum: %w[pending ready failed] },
        requested_at: { type: "string", format: "date-time" },
        ready_at: { type: "string", format: "date-time", nullable: true },
        download_url: { type: "string", nullable: true },
        data: { type: "object", nullable: true, additionalProperties: true }
      },
      required: %w[id status requested_at]
    },
    "AccountExportResponse" => {
      type: "object",
      properties: {
        export: { oneOf: [ { "$ref" => "#/components/schemas/AccountExport" }, { type: "null" } ] }
      },
      required: %w[export]
    },
    "AccountExportData" => {
      type: "object",
      additionalProperties: true
    },
    "AccountTwoFactorSetupResponse" => {
      type: "object",
      properties: {
        secret: { type: "string" },
        otpauth_uri: { type: "string" }
      },
      required: %w[secret otpauth_uri]
    },
    "AccountTwoFactorStatusResponse" => {
      type: "object",
      properties: {
        enabled: { type: "boolean" },
        enabled_at: { type: "string", format: "date-time", nullable: true }
      },
      required: %w[enabled enabled_at]
    },
    "AccountTwoFactorVerifyResponse" => {
      type: "object",
      properties: {
        status: { type: "string" },
        recovery_codes: { type: "array", items: { type: "string" } }
      },
      required: %w[status recovery_codes]
    },
    "AccountTwoFactorDisableResponse" => {
      type: "object",
      properties: {
        status: { type: "string" }
      },
      required: %w[status]
    },
    # Request payloads
    "AccountUpdateRequest" => {
      type: "object",
      properties: {
        account: {
          type: "object",
          properties: {
            name: { type: "string" }
          },
          required: %w[name]
        }
      },
      required: %w[account]
    },
    "ChangePasswordRequest" => {
      oneOf: [
        {
          type: "object",
          properties: {
            password: {
              type: "object",
              properties: {
                current_password: { type: "string" },
                new_password: { type: "string" }
              },
              required: %w[current_password new_password]
            }
          },
          required: %w[password]
        },
        {
          type: "object",
          properties: {
            current_password: { type: "string" },
            new_password: { type: "string" }
          },
          required: %w[current_password new_password]
        }
      ]
    },
    "ChangeEmailRequest" => {
      oneOf: [
        {
          type: "object",
          properties: {
            email: {
              type: "object",
              properties: {
                new_email_address: { type: "string", format: "email" },
                current_password: { type: "string" }
              },
              required: %w[new_email_address current_password]
            }
          },
          required: %w[email]
        },
        {
          type: "object",
          properties: {
            new_email_address: { type: "string", format: "email" },
            current_password: { type: "string" }
          },
          required: %w[new_email_address current_password]
        }
      ]
    },
    "NotificationPreferencesUpdateRequest" => {
      type: "object",
      properties: {
        account: {
          type: "object",
          properties: {
            notification_preferences: { "$ref" => "#/components/schemas/NotificationPreferences" }
          },
          required: %w[notification_preferences]
        }
      },
      required: %w[account]
    },
    "AccountDeleteRequest" => {
      oneOf: [
        {
          type: "object",
          properties: {
            account: {
              type: "object",
              properties: {
                current_password: { type: "string" },
                confirmation: { type: "string", enum: [ "DELETE" ] }
              },
              required: %w[current_password confirmation]
            }
          },
          required: %w[account]
        },
        {
          type: "object",
          properties: {
            current_password: { type: "string" },
            confirmation: { type: "string", enum: [ "DELETE" ] }
          },
          required: %w[current_password confirmation]
        }
      ]
    },
    "AccountTwoFactorVerifyRequest" => {
      oneOf: [
        {
          type: "object",
          properties: {
            account: {
              type: "object",
              properties: {
                code: { type: "string" }
              },
              required: %w[code]
            }
          },
          required: %w[account]
        },
        {
          type: "object",
          properties: {
            code: { type: "string" }
          },
          required: %w[code]
        }
      ]
    },
    "AccountTwoFactorDisableRequest" => {
      oneOf: [
        {
          type: "object",
          properties: {
            account: {
              type: "object",
              properties: {
                current_password: { type: "string" },
                code: { type: "string" }
              },
              required: %w[current_password code]
            }
          },
          required: %w[account]
        },
        {
          type: "object",
          properties: {
            current_password: { type: "string" },
            code: { type: "string" }
          },
          required: %w[current_password code]
        }
      ]
    },
    "SignupRequest" => {
      description: "User registration payload accepted by /api/v1/signup (and legacy /api/v1/users).",
      oneOf: [
        {
          type: "object",
          properties: {
            user: {
              type: "object",
              properties: {
                name: { type: "string" },
                email_address: { type: "string", format: "email" },
                password: { type: "string" },
                password_confirmation: { type: "string" }
              },
              required: %w[name email_address password password_confirmation]
            }
          },
          required: %w[user]
        },
        {
          type: "object",
          properties: {
            name: { type: "string" },
            email_address: { type: "string", format: "email" },
            password: { type: "string" },
            password_confirmation: { type: "string" }
          },
          required: %w[name email_address password password_confirmation]
        }
      ]
    },
    "LoginRequest" => {
      description: "Login payload accepted by /api/v1/login (nested or flat), with optional 2FA code fields.",
      oneOf: [
        {
          type: "object",
          properties: {
            session: {
              type: "object",
              properties: {
                email_address: { type: "string", format: "email" },
                password: { type: "string" },
                otp: { type: "string" },
                recovery_code: { type: "string" },
                recoveryCode: { type: "string" }
              },
              required: %w[email_address password]
            }
          },
          required: %w[session]
        },
        {
          type: "object",
          properties: {
            email_address: { type: "string", format: "email" },
            password: { type: "string" },
            otp: { type: "string" },
            recovery_code: { type: "string" }
          },
          required: %w[email_address password]
        },
        {
          type: "object",
          properties: {
            emailAddress: { type: "string", format: "email" },
            password: { type: "string" },
            otp: { type: "string" },
            recoveryCode: { type: "string" }
          },
          required: %w[emailAddress password]
        }
      ]
    },
    "RefreshRequest" => {
      description: "Session refresh payload accepted by /api/v1/session/refresh (nested or flat).",
      oneOf: [
        {
          type: "object",
          properties: {
            session: {
              type: "object",
              properties: {
                refresh_token: { type: "string" }
              },
              required: %w[refresh_token]
            }
          },
          required: %w[session]
        },
        {
          type: "object",
          properties: {
            refresh_token: { type: "string" }
          },
          required: %w[refresh_token]
        },
        {
          type: "object",
          properties: {
            refreshToken: { type: "string" }
          },
          required: %w[refreshToken]
        }
      ]
    },
    "AuctionUpsert" => {
      type: "object",
      description: "Attributes accepted when creating or updating an auction via admin endpoints.",
      properties: {
        auction: {
          type: "object",
          properties: {
            title: { type: "string" },
            description: { type: "string" },
            image_url: {
              type: "string",
              nullable: true,
              description: "Auction image reference. Upload proxy paths and legacy upload URLs are accepted; stored values are normalized when possible."
            },
            is_adult: { type: "boolean", nullable: true, description: "Marks the auction as adult inventory (restricted to afterdark storefront + age gate)." },
            is_marketplace: { type: "boolean", nullable: true, description: "Marks the auction as marketplace-curated inventory (restricted to marketplace storefront)." },
            status: { type: "string", enum: STATUSES, nullable: true },
            start_date: { type: "string", format: "date-time", nullable: true },
            end_time: { type: "string", format: "date-time", nullable: true },
            current_price: { type: "number", format: "float", nullable: true }
          },
          required: %w[title description]
        }
      },
      required: %w[auction]
    },
    "BidPackUpsert" => {
      type: "object",
      description: "Attributes accepted when creating or updating bid packs via admin endpoints.",
      properties: {
        bid_pack: {
          type: "object",
          properties: {
            name: { type: "string" },
            price: { type: "number", format: "float" },
            bids: { type: "integer" },
            highlight: { type: "boolean", nullable: true },
            description: { type: "string", nullable: true },
            status: { type: "string", enum: BID_PACK_STATUSES, nullable: true },
            active: { type: "boolean", nullable: true }
          },
          required: %w[name price bids]
        }
      },
      required: %w[bid_pack]
    },
    "AuditLogCreate" => {
      type: "object",
      properties: {
        audit: {
          type: "object",
          properties: {
            action: { type: "string" },
            target_type: { type: "string", nullable: true },
            target_id: { type: "integer", nullable: true },
            payload: { type: "object", additionalProperties: true }
          },
          required: %w[action]
        }
      },
      required: %w[audit]
    },
    "PaymentRefundRequest" => {
      type: "object",
      properties: {
        amount_cents: { type: "integer", minimum: 0 },
        full_refund: { type: "boolean", description: "Set true to refund the full remaining amount. Do not send amount_cents when true." },
        reason: { type: "string", nullable: true }
      },
      oneOf: [
        { required: %w[amount_cents] },
        {
          required: %w[full_refund],
          properties: {
            full_refund: { type: "boolean", enum: [ true ] }
          }
        }
      ],
      required: []
    },
    "AdminUserUpdate" => {
      type: "object",
      properties: {
        user: {
          type: "object",
          properties: {
            name: { type: "string", nullable: true },
            email_address: { type: "string", format: "email", nullable: true },
            role: { type: "string", enum: %w[user admin superadmin], nullable: true },
            status: { type: "string", enum: %w[active disabled banned suspended], nullable: true },
            email_verified: { type: "boolean", nullable: true },
            email_verified_at: { type: "string", format: "date-time", nullable: true }
          }
        }
      },
      required: %w[user]
    },
    "MaintenanceToggle" => {
      type: "object",
      properties: {
        enabled: { type: "boolean" }
      },
      required: %w[enabled]
    },
    "BidPlacementResponse" => {
      type: "object",
      description: "Response envelope returned after placing a bid.",
      properties: {
        success: { type: "boolean" },
        bid: { "$ref" => "#/components/schemas/Bid" },
        bidCredits: { type: "integer" }
      },
      required: %w[success bid bidCredits]
    }
  }.freeze

  def self.inject_into(spec_hash)
    spec_hash[:components] ||= {}
    spec_hash[:components][:schemas] ||= {}
    spec_hash[:components][:schemas].merge!(SCHEMAS)
    spec_hash
  end

  def self.register_type_parsers!
    existing_parsers = OasCore::JsonSchemaGenerator.instance_variable_get(:@custom_type_parsers) || {}
    OasCore::JsonSchemaGenerator.instance_variable_set(:@custom_type_parsers, {})

    OasCore::JsonSchemaGenerator.register_type_parser(
      ->(type) { SCHEMAS.key?(type) },
      ->(type, _required) { { "$ref" => "#/components/schemas/#{type}" } }
    )

    existing_parsers.each do |matcher, parser|
      OasCore::JsonSchemaGenerator.register_type_parser(matcher, parser)
    end
  end
end

# Ensure canonical schemas are registered and injected into the generated specification.
OasSchemasRuntime.register_type_parsers!

# Backward-compatible alias for any older references.
OasSchemas = OasSchemasRuntime unless defined?(OasSchemas)

module OasRails
  class << self
    unless method_defined?(:build_without_canonical_schemas)
      alias_method :build_without_canonical_schemas, :build

      def build(...)
        OasSchemasRuntime.inject_into(build_without_canonical_schemas(...))
      end
    end
  end
end
