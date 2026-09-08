# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # The sheet that picks the amenities a property offers. Property Settings
    # used to hold this field and now links here, so the selection sits beside
    # the guest details it drives. Onboarding keeps its own first-run picker.
    class AmenitySelectionsController < HotelPortal::GuestContent::BaseController
      include SheetActionCompletion

      def edit
        load_form_state(selected: @hotel.amenities)
        render layout: false
      end

      def update
        result = HotelPortal::Amenities::UpdateSelection.call(hotel: @hotel, slugs: selected_slugs)

        if result.success?
          complete_sheet_action(
            destination: hotel_guest_amenities_path(@hotel),
            notice: "Property amenities updated successfully.",
            frame: sheet_frame
          )
        else
          load_form_state(selected: selected_slugs)
          render :edit, layout: false, status: :unprocessable_content
        end
      end

      private

      def selected_slugs
        Array(params.fetch(:hotel, {}).permit(amenities: [])[:amenities]).compact_blank
      end

      # Every hotel amenity is offered here, not only the selected ones, and each
      # row carries the guest-detail status of its amenity.
      def load_form_state(selected:)
        @rows = HotelPortal::GuestContent::AmenityRow.build(hotel: @hotel, amenities: Amenity.hotel.ordered)
        @categories = @rows.map(&:category).compact_blank.uniq.sort
        @selected_slugs = Array(selected).compact_blank.map(&:to_s)
        @groups = grouped_rows
      end

      # What the property already offers comes first, under its own heading, so
      # an operator reopening the sheet reads the current selection before the
      # catalog. The rest keep their category headings. Grouping is fixed at
      # load: a row that jumped between groups on every click would move under
      # the pointer.
      def grouped_rows
        selected, remaining = @rows.partition { |row| @selected_slugs.include?(row.slug) }
        groups = []
        groups << [ "Selected", selected ] if selected.any?
        groups.concat(remaining.group_by(&:category).sort_by { |category, _rows| category.to_s })
      end

      def sheet_frame
        turbo_frame_request_id.presence || "settings_action_sheet"
      end
    end
  end
end
