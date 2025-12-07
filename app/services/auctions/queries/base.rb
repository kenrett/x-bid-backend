module Auctions
  module Queries
    class Base
      attr_reader :params, :records

      def self.call(params: {})
        new(params: params).call
      end

      def initialize(params: {})
        @params = (params || {}).dup.freeze
        @records = nil
      end

      def call
        raise NotImplementedError, "#{self.class.name} must implement #call"
      end
    end
  end
end
