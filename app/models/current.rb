class Current < ActiveSupport::CurrentAttributes
  attribute :request_id
  attribute :user_id
  attribute :observation_buffer
end
