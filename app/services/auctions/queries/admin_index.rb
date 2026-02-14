module Auctions
  module Queries
    class AdminIndex < Base
      DEFAULT_PER_PAGE = 20
      MAX_PER_PAGE = 100

      attr_reader :records, :meta

      def initialize(params: {}, relation: Auction.all)
        super(params: params)
        @relation = relation
        @meta = {}
      end

      def call
        scope = base_scope
        scope = filter_by_status(scope)
        scope = filter_by_storefront(scope)
        scope = filter_by_search(scope)
        scope = filter_by_start_date_range(scope)
        scope = apply_sort(scope)

        total_count = count_scope(scope)
        scope = apply_pagination(scope)

        @records = scope
        @meta = build_meta(total_count)

        self
      end

      private

      attr_reader :relation

      def base_scope
        relation
          .select(
            :id,
            :title,
            :description,
            :start_date,
            :end_time,
            :current_price,
            :image_url,
            :status,
            :storefront_key,
            :is_adult,
            :is_marketplace,
            :winning_user_id
          )
          .includes(:winning_user)
      end

      def filter_by_status(scope)
        return scope unless params[:status].present?

        normalized = Auctions::Status.from_api(params[:status]) || params[:status]
        return scope unless normalized

        scope.where(status: normalized)
      end

      def filter_by_search(scope)
        return scope unless params[:search].present?

        term = "%#{params[:search].to_s.downcase}%"
        scope.where("LOWER(auctions.title) LIKE :term OR LOWER(auctions.description) LIKE :term", term: term)
      end

      def filter_by_storefront(scope)
        return scope unless params[:storefront_key].present?

        storefront_key = params[:storefront_key].to_s.strip.downcase
        return scope.none unless StorefrontKeyable::CANONICAL_KEYS.include?(storefront_key)

        scope.where(storefront_key: storefront_key)
      end

      def filter_by_start_date_range(scope)
        from = parse_time(params[:start_date_from])
        to = parse_time(params[:start_date_to])

        scope = scope.where("auctions.start_date >= ?", from) if from
        scope = scope.where("auctions.start_date <= ?", to) if to
        scope
      end

      def apply_sort(scope)
        column = sort_column
        direction = sort_direction
        scope.order(column => direction.to_sym)
      end

      def count_scope(scope)
        scope.except(:select, :order, :includes).count
      end

      def apply_pagination(scope)
        scope.offset((page_number - 1) * per_page).limit(per_page)
      end

      def sort_column
        allowed = {
          "start_date" => :start_date,
          "end_time" => :end_time,
          "created_at" => :created_at,
          "title" => :title,
          "status" => :status
        }
        allowed[params[:sort].to_s] || :start_date
      end

      def sort_direction
        %w[asc desc].include?(params[:direction].to_s.downcase) ? params[:direction].to_s.downcase : "desc"
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

      def build_meta(total_count)
        total_pages = (total_count.to_f / per_page).ceil
        {
          page: page_number,
          per_page: per_page,
          total_pages: total_pages,
          total_count: total_count
        }
      end

      def parse_time(value)
        return if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
