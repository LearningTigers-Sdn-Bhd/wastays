# Policy, FAQ, and Attractions Details

## Hotel Policy

- Answers check-in/out times, cancellation policy, hotel rules
- Reads from `HotelKnowledgeDocument` (category: policy), falls back to `hotel.property_policy`
- Returns structured policy facts or unavailable state when no policy data exists

## Hotel FAQ

- Returns hotel FAQ content when provided by the hotel
- Returns unavailable state when FAQ is blank

## Nearby Attractions

- Returns ordered nearby attractions with name, description, address, city, and country
- Renders full attraction list

## Booking Context

- Returns structured booking rows for matching phone number
- Returns empty list when no active bookings exist
- Used to render existing booking context in a predictable reply format
