# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class SummariesController < OverviewBaseController
        def show
          render :show, layout: false
        end
      end
    end
  end
end
