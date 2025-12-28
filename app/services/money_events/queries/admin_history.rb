module MoneyEvents
  module Queries
    class AdminHistory < Base
      Entry = Struct.new(:money_event, :source, keyword_init: true)

      def initialize(params: {}, relation: MoneyEvent.all)
        super(params: params)
        @relation = relation
      end

      def call
        user_id = params[:user_id]
        raise ArgumentError, "user_id is required" if user_id.blank?

        events = relation
          .where(user_id: user_id)
          .order(occurred_at: :asc, id: :asc)

        sources_by_type = load_sources(events)

        @records = events.map do |event|
          Entry.new(
            money_event: event,
            source: sources_by_type.dig(event.source_type, event.source_id.to_s)
          )
        end

        self
      end

      private

      attr_reader :relation

      def load_sources(events)
        supported = {
          "Bid" => Bid
        }

        ids_by_type = Hash.new { |h, k| h[k] = [] }
        events.each do |event|
          next if event.source_type.blank? || event.source_id.blank?
          next unless supported.key?(event.source_type)

          ids_by_type[event.source_type] << event.source_id.to_s
        end

        ids_by_type.transform_values!(&:uniq)

        sources_by_type = {}
        ids_by_type.each do |source_type, source_ids|
          model = supported.fetch(source_type)
          integer_ids = source_ids.filter_map { |id| Integer(id, exception: false) }.uniq
          records = model.where(id: integer_ids).to_a
          sources_by_type[source_type] = records.index_by { |r| r.id.to_s }
        end

        sources_by_type
      end
    end
  end
end
