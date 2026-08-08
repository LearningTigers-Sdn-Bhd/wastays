require 'rails_helper'

RSpec.describe RatePlans::OccupancyLadder do
  it 'steps up and down from the primary occupancy' do
    matrix = described_class.call(
      anchor: 750, max_adults: 4, primary_occupancy: 2,
      increase_by: 180, decrease_by: 100
    )

    expect(matrix).to eq(1 => 650.to_d, 2 => 750.to_d, 3 => 930.to_d, 4 => 1110.to_d)
  end

  it 'covers every adult count the category can seat' do
    matrix = described_class.call(anchor: 320, max_adults: 3, primary_occupancy: 2)

    expect(matrix.keys).to eq([ 1, 2, 3 ])
  end

  it 'takes a percentage step against the anchor rather than compounding' do
    matrix = described_class.call(
      anchor: 100, max_adults: 3, primary_occupancy: 1,
      increase_by: 10, increase_unit: "percent"
    )

    expect(matrix[3]).to eq(120.to_d)
  end

  it 'floors a price at zero rather than going negative' do
    matrix = described_class.call(
      anchor: 100, max_adults: 3, primary_occupancy: 3, decrease_by: 80
    )

    expect(matrix[1]).to eq(0.to_d)
  end

  it 'clamps a primary occupancy beyond the category capacity' do
    matrix = described_class.call(
      anchor: 200, max_adults: 2, primary_occupancy: 5, decrease_by: 50
    )

    expect(matrix).to eq(1 => 150.to_d, 2 => 200.to_d)
  end
end
