module Api
  module V1
    class LegacyController < ApplicationController
      # Intentionally unauthenticated: legacy endpoints should behave consistently (404),
      # and not leak as auth failures.
      #
      # @summary Legacy endpoint removed
      # @response Not found (404) [Error]
      def not_found
        render_error(code: :not_found, message: "Endpoint not found", status: :not_found)
      end
    end
  end
end
