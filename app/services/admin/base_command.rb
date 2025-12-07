module Admin
  class BaseCommand
    def initialize(actor:, **kwargs)
      @actor = actor
      assign_attributes(kwargs)
    end

    def call
      return forbidden unless authorized?

      perform
    end

    private

    attr_reader :actor

    def perform
      raise NotImplementedError, "#{self.class.name} must implement #perform"
    end

    def authorized?
      actor&.admin? || actor&.superadmin?
    end

    def forbidden
      ServiceResult.fail("Admin privileges required", code: :forbidden)
    end

    def assign_attributes(kwargs)
      kwargs.each { |key, value| instance_variable_set("@#{key}", value) }
    end
  end
end
