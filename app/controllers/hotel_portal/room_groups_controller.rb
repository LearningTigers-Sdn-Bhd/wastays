# frozen_string_literal: true

class HotelPortal::RoomGroupsController < HotelPortal::BaseController
  before_action :set_hotel
  before_action :authorize_hotel
  before_action :set_room_group, only: [ :edit, :update, :destroy ]

  def index
    @room_groups = @hotel.room_groups.order(:name)
    @room_group = @hotel.room_groups.build
  end

  def create
    @room_group = @hotel.room_groups.build(room_group_params)

    if @room_group.save
      redirect_to hotel_room_groups_path(@hotel), notice: "Room group created successfully."
    else
      @room_groups = @hotel.room_groups.order(:name)
      render :index, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @room_group.update(room_group_params)
      redirect_to hotel_room_groups_path(@hotel), notice: "Room group updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @room_group.destroy
      redirect_to hotel_room_groups_path(@hotel), notice: "Room group deleted successfully."
    else
      redirect_to hotel_room_groups_path(@hotel), alert: "Cannot delete room group."
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

  def room_group_params
    params.require(:room_group).permit(:name)
  end
end
