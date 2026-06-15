# frozen_string_literal: true

module HotelPortal
  module DashboardHelper
    def dashboard_tab_classes
      "group inline-flex h-9 items-center gap-2 whitespace-nowrap rounded-lg px-4 text-sm font-medium " \
      "text-slate-600 transition-all duration-150 hover:bg-slate-50 hover:text-slate-900 " \
      "data-[active=true]:bg-blue-600 data-[active=true]:font-semibold data-[active=true]:text-white"
    end

    def dashboard_tab_container_classes
      "overflow-x-auto rounded-xl border border-slate-200 bg-white p-1.5 shadow-sm"
    end
  end
end
