module Public
  module Concierge
    module Stays
      class DoNotDisturbsController < BaseController
        def update
          result = ::Guest::ToggleDndService.new(booking: stay_booking).call

          if result.success?
            redirect_to stay_path, notice: result.message
          else
            redirect_to stay_path, alert: result.error
          end
        end
      end
    end
  end
end
