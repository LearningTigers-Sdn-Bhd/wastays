# frozen_string_literal: true

module PanelsUI
  module Navigation
    # Shared value object for a single navigation entry (sidebar link, breadcrumb
    # node, tab target). Supersedes the per-portal `NavItem`/`AdminItem` Structs that
    # each `*/navigation_helper.rb` used to declare: it carries every field any portal
    # needs, so admin can ignore `permission`/`plan_feature` while hotel uses them all.
    #
    # Immutable and free of view/permission logic on purpose — helpers keep computing
    # `active:` and doing permission/plan filtering, then hand finished Items to the
    # PanelsUI navigation components to render.
    #
    #   Navigation::Item.new(label: "Bookings", path: hotel_bookings_path(hotel),
    #                        icon: "calendar-days", active: controller_name == "bookings",
    #                        permission: "view_bookings")
    #
    # `children` nests Items one level (a collapsible sidebar group / breakdown menu).
    Item = Data.define(
      :label, :path, :icon, :active, :search_text, :external,
      :children, :permission, :permission_scope, :plan_feature, :active_paths,
      :turbo_frame
    ) do
      def initialize(label:, path: nil, icon: nil, active: false, search_text: nil,
                     external: false, children: [], permission: nil,
                     permission_scope: nil, plan_feature: nil, active_paths: [],
                     turbo_frame: nil)
        frozen_children = Array(children).dup.freeze
        super(
          label:, path:, icon:, active:, search_text:,
          external:, children: frozen_children, permission:,
          permission_scope:, plan_feature:, active_paths: Array(active_paths).dup.freeze,
          turbo_frame:
        )
      end

      def active? = active
      def external? = external
      def children? = children.any?
      def leaf? = children.empty?
    end
  end
end
