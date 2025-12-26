module Credits
  module Queries
    class LedgerForUser
      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      attr_reader :records, :meta

      def self.call(user:, params: {}, relation: CreditTransaction.all)
        new(user: user, params: params, relation: relation).call
      end

      def initialize(user:, params: {}, relation: CreditTransaction.all)
        raise ArgumentError, "User must be provided" unless user

        @user = user
        @params = (params || {}).dup
        @relation = relation
        @records = []
        @meta = {}
      end

      def call
        scope = base_scope
        page_records = fetch_page(scope)

        @meta = {
          page: page_number,
          per_page: per_page,
          has_more: page_records.length > per_page
        }

        @records = page_records.first(per_page)
        self
      end

      private

      attr_reader :user, :params, :relation

      def base_scope
        relation
          .where(user_id: user.id)
          .order(created_at: :desc, id: :desc)
      end

      def fetch_page(scope)
        scope
          .offset((page_number - 1) * per_page)
          .limit(per_page + 1)
          .to_a
      end

      def page_number
        value = params[:page].to_i
        value.positive? ? value : 1
      end

      def per_page
        value = params[:per_page].to_i
        return DEFAULT_PER_PAGE if value <= 0

        [ value, MAX_PER_PAGE ].min
      end
    end
  end
end
