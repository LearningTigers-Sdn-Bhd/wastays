module Concierge
  class Result < Struct.new(
    :success?,
    :booking,
    :request,
    :check_out_request,
    :room_number,
    :error_code,
    :message,
    keyword_init: true
  )
    def self.success(**attributes)
      new(success?: true, **attributes)
    end

    def self.failure(**attributes)
      new(success?: false, **attributes)
    end
  end
end
