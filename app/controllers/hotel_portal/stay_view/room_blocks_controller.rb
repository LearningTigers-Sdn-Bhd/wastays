# frozen_string_literal: true

module HotelPortal
  module StayView
    class RoomBlocksController < BaseController
      before_action -> { require_capability!(:manage_room_blocks) }
      before_action :set_room_block, only: %i[edit update destroy finish]

      def new
        room_type = current_hotel.room_types.find(params[:room_type_id])
        room_number = params[:room_number].to_s
        raise ActiveRecord::RecordNotFound unless ::Rooms::DirectoryQuery.for_room_type(room_type).include?(room_number)

        @room_block = current_hotel.room_blocks.build(
          room_type:,
          room_number:,
          start_date: params[:start_date].presence || stay_view_state.date_window.start_date,
          end_date: params[:start_date].presence || stay_view_state.date_window.start_date,
          block_type: "maintenance"
        )
      end

      def edit; end

      def create
        attributes = room_block_params
        @room_block = current_hotel.room_blocks.build(attributes)
        result = Rooms::ManageBlock.new(hotel: current_hotel, user: current_user, params: attributes).create
        return respond_with_board("Room blocked.") if result.success?

        add_error(@room_block, result.error)
        render_sheet_error("hotel_portal/stay_view/room_blocks/form")
      end

      def update
        result = Rooms::ManageBlock.new(hotel: current_hotel, user: current_user, block: @room_block, params: room_block_params).update
        return respond_with_board("Room block updated.") if result.success?

        add_error(@room_block, result.error)
        render_sheet_error("hotel_portal/stay_view/room_blocks/form")
      end

      def destroy
        result = Rooms::ManageBlock.new(hotel: current_hotel, user: current_user, block: @room_block).destroy
        return respond_with_board("Room block deleted.") if result.success?

        add_error(@room_block, result.error)
        render_sheet_error("hotel_portal/stay_view/room_blocks/form")
      end

      # "Return to service" in the sheet. The block ends either way; the status
      # staff picked is what the room is worth once it does.
      def finish
        target_status = params[:room_status].to_s
        was_active_today = @room_block.active_on?(current_hotel.business_date_for)
        result = Rooms::ManageBlock.new(hotel: current_hotel, user: current_user, block: @room_block).finish(target_status: target_status)
        return respond_with_board(returned_to_service_notice(target_status, was_active_today)) if result.success?

        add_error(@room_block, result.error)
        render_sheet_error("hotel_portal/stay_view/room_blocks/form")
      end

      private

      # Staff are told what the room now needs, not that a record changed state.
      def returned_to_service_notice(target_status, was_active_today)
        room = "Room #{@room_block.room_number}"
        return "#{room} is back in service." unless was_active_today

        if target_status == "ready"
          "#{room} is back in service and ready to sell."
        else
          "#{room} is back in service and sent to housekeeping."
        end
      end

      def set_room_block
        @room_block = current_hotel.room_blocks.includes(:room_type).find(params[:id])
      end

      def room_block_params
        attributes = params.require(:room_block).permit(:room_type_id, :room_number, :start_date, :end_date, :block_type, :reason, :notes)
        room_type = current_hotel.room_types.find(attributes[:room_type_id])
        unless ::Rooms::DirectoryQuery.for_room_type(room_type).include?(attributes[:room_number])
          raise ActiveRecord::RecordNotFound
        end

        attributes
      end
    end
  end
end
