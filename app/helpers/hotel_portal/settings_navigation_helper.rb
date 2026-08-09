# frozen_string_literal: true

module HotelPortal
  module SettingsNavigationHelper
    NavSection = PanelsUI::Navigation::Section
    NavItem = PanelsUI::Navigation::Item
    SETTINGS_GROUPS = {
      general: { label: "General", icon: "settings", permission: "manage_hotel_profile" },
      property: { label: "Property", icon: "building-2", permission: "manage_hotel_profile" },
      commercial: { label: "Commercial", icon: "badge-dollar-sign", permission: "manage_hotel_profile", sidebar_menu: true },
      finance: { label: "Finance", icon: "landmark", permission: [ "manage_account", "manage_hotel_profile" ] },
      guest_content: { label: "Guest Content", icon: "message-square", permission: "manage_hotel_profile" },
      team: { label: "Team", icon: "users", permission: "manage_users" }
    }.freeze

    def hotel_settings_sidebar_sections
      return @_hotel_settings_sidebar_sections if defined?(@_hotel_settings_sidebar_sections)

      @_hotel_settings_sidebar_sections = [
        NavSection.new(label: "Settings", items: settings_navigation_groups.map do |key, group|
          children = if group[:sidebar_menu]
            group[:tabs].map do |tab|
              NavItem.new(
                label: tab[:label],
                path: tab[:path],
                icon: tab[:icon],
                active: tab[:active]
              )
            end
          else
            []
          end

          NavItem.new(
            label: group[:label],
            path: group[:tabs].first&.fetch(:path),
            icon: group[:icon],
            active: settings_group_active?(key),
            permission: group[:permission],
            children: children,
            active_paths: group[:tabs].map { |tab| tab[:path] }
          )
        end)
      ]
    end

    def hotel_settings_visible_sidebar_sections
      hotel_visible_sidebar_sections(hotel_settings_sidebar_sections)
    end

    def hotel_settings_landing_path
      hotel_settings_visible_sidebar_sections.first&.items&.first&.path
    end

    def settings_tabs_for_group(group)
      settings_navigation_groups.dig(group, :tabs) || []
    end

    def settings_group_active?(group)
      settings_tabs_for_group(group).any? { |tab| tab[:active] }
    end

    def settings_group_sidebar_menu?(group)
      SETTINGS_GROUPS.dig(group, :sidebar_menu) == true
    end

    def hotel_settings_breadcrumb_parts
      return breadcrumb_override if respond_to?(:breadcrumbs_overridden?) && breadcrumbs_overridden?

      group = active_settings_group
      active_tab = settings_tabs_for_group(group).find { |tab| tab[:active] }
      parts = [ settings_root_breadcrumb_part ]
      parts << settings_group_breadcrumb_part(group) if group
      if active_tab
        parts << {
          type: :menu,
          label: active_tab[:label],
          path: active_tab[:path],
          siblings: settings_tabs_for_group(group).map { |tab| { label: tab[:label], path: tab[:path] } }
        }
      end
      parts + (respond_to?(:breadcrumb_appends) ? breadcrumb_appends : [])
    end

    def render_hotel_settings_breadcrumbs
      render PanelsUI::Breadcrumb.new(id: "hotel-breadcrumb", parts: hotel_settings_breadcrumb_parts)
    end

    private

    def settings_active_page
      @presenter&.active_page || params[:settings_page].presence || "general"
    end

    def active_settings_group
      SETTINGS_GROUPS.each_key.find { |group| settings_group_active?(group) }
    end

    def settings_root_breadcrumb_part
      { type: :menu, label: "Settings", path: hotel_settings_landing_path }
    end

    def settings_group_breadcrumb_part(group)
      active_section = hotel_settings_visible_sidebar_sections.first
      active_item = active_section&.items&.find { |item| item.active? }

      {
        type: :section,
        label: active_item&.label || group.to_s.humanize
      }
    end

    def settings_navigation_groups
      @_settings_navigation_groups ||= SETTINGS_GROUPS.to_h do |key, group|
        [ key, group.merge(tabs: settings_group_tabs(key)) ]
      end
    end

    def settings_group_tabs(group)
      case group
      when :general
        [
          hotel_permission_granted?("manage_hotel_profile") ? { key: "general", label: "General", path: hotel_general_settings_path(current_hotel), icon: "settings", active: controller_name == "settings" && settings_active_page == "general" } : nil,
          hotel_permission_granted?("manage_hotel_profile") && current_hotel.allow_boat_information? ? { key: "boat", label: "Boat Settings", path: hotel_boat_settings_path(current_hotel), icon: "ship", active: controller_name.in?(%w[settings boat_schedules]) && settings_active_page == "boat" } : nil,
          hotel_permission_granted?("manage_hotel_profile") ? { key: "notifications", label: "Notifications", path: hotel_notification_settings_path(current_hotel), icon: "bell", active: controller_name == "settings" && settings_active_page == "notifications" } : nil,
          { key: "plan", label: "Plan & Billing", path: hotel_plan_path(current_hotel), icon: "layers", active: controller_name == "plans" }
        ].compact
      when :property
        [
          { key: "hotel-details", label: "Hotel Details", path: edit_hotel_profile_path(current_hotel), icon: "building-2", active: controller_name == "profiles" },
          { key: "room-inventory", label: "Room Inventory", path: hotel_room_types_path(current_hotel), icon: "layers", active: controller_name.in?(%w[room_types rate_plan_attachments rate_plans rate_plan_room_pricings]) },
          { key: "nearby-attractions", label: "Nearby Attractions", path: hotel_nearby_attractions_path(current_hotel), icon: "map-pin", active: controller_name == "nearby_attractions" }
        ]
      when :commercial
        [
          hotel_permission_granted?("manage_hotel_profile") ? { key: "taxes-fees", label: "Taxes & Fees", path: hotel_taxes_fees_path(current_hotel), icon: "receipt", active: controller_name.in?(%w[taxes_fees hotel_taxes]) } : nil,
          hotel_permission_granted?("manage_hotel_profile") ? { key: "extra-charges", label: "Extra Charges", path: hotel_extra_charges_path(current_hotel), icon: "circle-plus", active: controller_name == "extra_charges" } : nil,
          hotel_permission_granted?("manage_hotel_profile") ? { key: "discounts", label: "Discounts", path: hotel_discounts_path(current_hotel), icon: "badge-percent", active: controller_name == "discounts" } : nil,
          hotel_permission_granted?("manage_hotel_profile") ? { key: "payment-methods", label: "Payment Methods", path: hotel_payment_methods_path(current_hotel), icon: "credit-card", active: controller_name == "payment_methods" } : nil,
          hotel_permission_granted?("manage_hotel_profile") ? { key: "room-revenue", label: "Room Revenue", path: hotel_room_revenue_path(current_hotel), icon: "bed-double", active: controller_name.in?(%w[room_revenue reservation_policies]) } : nil
        ].compact
      when :finance
        [
          hotel_permission_granted?("manage_account") ? { key: "banking", label: "Banking Details", path: hotel_banking_details_settings_path(current_hotel), icon: "landmark", active: controller_name == "settings" && settings_active_page == "banking" } : nil,
          hotel_permission_granted?("manage_hotel_profile") ? { key: "transaction-code-reference", label: "Transaction Code Reference", path: hotel_transaction_code_references_path(current_hotel), icon: "list", active: controller_name == "transaction_code_references" } : nil,
          hotel_permission_granted?("manage_general_ledger_maps") ? { key: "general-ledger-mappings", label: "General Ledger Mappings", path: hotel_general_ledger_maps_path(current_hotel), icon: "git-merge", active: controller_name == "general_ledger_maps" } : nil
        ].compact
      when :guest_content
        [
          { key: "ai-concierge", label: "AI Concierge", path: hotel_ai_concierge_settings_path(current_hotel), icon: "sparkles", active: controller_name == "settings" && settings_active_page == "ai" },
          { key: "policies", label: "Policies", path: hotel_knowledge_policies_path(current_hotel), icon: "file-text", active: controller_name == "knowledge_policies" },
          { key: "faqs", label: "FAQs", path: hotel_knowledge_faqs_path(current_hotel), icon: "circle-question-mark", active: controller_name == "knowledge_faqs" },
          { key: "general-info", label: "General Info", path: hotel_knowledge_general_infos_path(current_hotel), icon: "info", active: controller_name == "knowledge_general_infos" },
          { key: "knowledge-diagnostics", label: "Knowledge Diagnostics", path: hotel_knowledge_diagnostics_path(current_hotel), icon: "activity", active: controller_name == "knowledge_diagnostics" }
        ]
      when :team
        [
          { key: "staff-management", label: "Staff Management", path: hotel_users_path(current_hotel), icon: "users", active: controller_name.in?(%w[users staff_invitations]) },
          { key: "roles-permissions", label: "Roles & Permissions", path: hotel_roles_path(current_hotel), icon: "shield-check", active: controller_name == "roles" }
        ]
      else
        []
      end
    end
  end
end
