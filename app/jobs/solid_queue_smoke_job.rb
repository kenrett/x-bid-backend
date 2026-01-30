class SolidQueueSmokeJob < ApplicationJob
  queue_as :default

  def perform(token)
    Rails.cache.write("solid_queue_smoke:#{token}", Time.current.to_i)
  end
end
