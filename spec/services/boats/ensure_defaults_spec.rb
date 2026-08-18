require 'rails_helper'

RSpec.describe Boats::EnsureDefaults do
  let(:hotel) { create(:hotel, allow_boat_information: true) }

  it 'creates the meal service times' do
    described_class.call(hotel)

    setting = hotel.reload.hotel_boat_setting
    expect(setting.breakfast_time.strftime('%H:%M')).to eq('08:00')
    expect(setting.lunch_time.strftime('%H:%M')).to eq('12:00')
    expect(setting.dinner_time.strftime('%H:%M')).to eq('19:00')
  end

  it 'creates a generic timetable in both directions' do
    described_class.call(hotel)

    slots = hotel.reload.hotel_boat_schedules
    expect(slots.boat_in.in_service_order.map(&:time_of_day)).to eq(%w[09:00 12:00 17:00])
    expect(slots.boat_out.in_service_order.map(&:time_of_day)).to eq(%w[10:00 13:00 18:00])
  end

  it 'derives each slot\'s meals from the service times' do
    described_class.call(hotel)

    slots = hotel.reload.hotel_boat_schedules.in_service_order.index_by { |slot| [ slot.kind, slot.time_of_day ] }
    expect(slots[[ 'boat_in', '09:00' ]].meals).to eq(%i[lunch dinner])
    expect(slots[[ 'boat_in', '17:00' ]].meals).to eq(%i[dinner])
    expect(slots[[ 'boat_out', '10:00' ]].meals).to eq(%i[breakfast])
    expect(slots[[ 'boat_out', '18:00' ]].meals).to eq(%i[breakfast lunch])
  end

  it 'does nothing for a hotel without boat features' do
    hotel.update!(allow_boat_information: false)

    expect { described_class.call(hotel) }
      .to change(HotelBoatSetting, :count).by(0)
      .and change(HotelBoatSchedule, :count).by(0)
  end

  it 'leaves an existing timetable alone' do
    described_class.call(hotel)
    hotel.reload.hotel_boat_schedules.boat_in.in_service_order.first.update!(time: '06:30')

    expect { described_class.call(hotel) }.to change { hotel.hotel_boat_schedules.count }.by(1)
    expect(hotel.hotel_boat_schedules.boat_in.in_service_order.map(&:time_of_day)).to eq(%w[06:30 09:00 12:00 17:00])
  end
end
