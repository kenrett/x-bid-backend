require_relative "with_storefront_context"

class ApplicationJob < ActiveJob::Base
  include Jobs::WithStorefrontContext
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
