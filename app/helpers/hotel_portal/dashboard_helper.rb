# frozen_string_literal: true

module HotelPortal
  module DashboardHelper
    def dashboard_tab_classes
      "group inline-flex h-9 items-center gap-2 whitespace-nowrap rounded-lg px-4 text-sm font-medium " \
      "text-muted-foreground transition-all duration-150 hover:bg-muted hover:text-foreground " \
      "data-[active=true]:bg-blue-600 data-[active=true]:font-semibold data-[active=true]:text-primary-foreground"
    end

    def dashboard_tab_container_classes
      "overflow-x-auto rounded-xl border border-border bg-card p-1.5 shadow-sm"
    end
  end
end
