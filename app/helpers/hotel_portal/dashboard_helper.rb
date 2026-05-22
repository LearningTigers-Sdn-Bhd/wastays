# frozen_string_literal: true

module HotelPortal
  module DashboardHelper
    def dashboard_tab_classes
      "whitespace-nowrap px-5 py-2.5 text-sm font-semibold transition rounded-xl " \
      "data-[active=true]:bg-slate-900 data-[active=true]:text-white data-[active=true]:shadow-sm " \
      "text-slate-600 hover:bg-slate-100 hover:text-slate-900"
    end

    def dashboard_tab_container_classes
      "overflow-x-auto rounded-2xl border border-slate-200 bg-white/95 p-2 shadow-sm backdrop-blur"
    end
  end
end
