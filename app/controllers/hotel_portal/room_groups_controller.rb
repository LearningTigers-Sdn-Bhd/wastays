# frozen_string_literal: true

class HotelPortal::RoomGroupsController < HotelPortal::BaseController
  include OffcanvasTransactionCompletion

  before_action :set_hotel
  before_action :authorize_hotel
  before_action :set_room_group, only: [ :edit, :update, :destroy ]

  def index
    set_room_groups
    @room_group = @hotel.room_groups.build
  end

  def create
    @room_group = @hotel.room_groups.build(room_group_params)

    if @room_group.save
      offcanvas_transaction_response(
        destination: destination_path,
        notice: "Room group created successfully."
      )
    else
      set_room_groups
      render :index, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @room_group.update(room_group_params)
      offcanvas_transaction_response(
        destination: destination_path,
        notice: "Room group updated successfully."
      )
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @room_group.destroy
      offcanvas_transaction_response(
        destination: destination_path,
        notice: "Room group deleted successfully."
      )
    else
      respond_to do |format|
        format.html { redirect_to destination_path, alert: "Cannot delete room group." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "flash_toasts",
            partial: "shared/toast",
            locals: { key: "alert", value: "Cannot delete room group: #{@room_group.errors.full_messages.to_sentence}" }
          ), status: :unprocessable_content
        end
      end
    end
  end

  private

  def set_hotel
    @hotel = current_hotel
  end

  def authorize_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy
  end

  def set_room_group
    @room_group = @hotel.room_groups.find(params[:id])
  end

  def set_room_groups
    @room_groups = @hotel.room_groups.includes(:room_types).order(:name)
  end

  def destination_path
    hotel_room_types_path(@hotel)
  end

  def room_group_params
    params.require(:room_group).permit(:name)
  end
end
