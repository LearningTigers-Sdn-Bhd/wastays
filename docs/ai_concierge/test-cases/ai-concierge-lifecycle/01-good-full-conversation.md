# Good: Full Conversation Flow

## E2E Happy Path

1. guest sends greeting -> concierge responds with greeting
2. guest asks about executive suite -> room info returned
3. guest asks `late may` -> timing collected
4. guest says `3 days 2 nights` -> duration collected
5. guest says `2 adults` -> search runs
6. grouped options returned with prices
7. guest says `ocean villa king option 1` -> option selected
8. confirmation asked -> guest says `yes`
9. booking URL returned with total and expiry

## Interruption and Resume

1. guest booking -> asks `any hotel policies?` -> policy reply -> `ok i want executive on may 22` -> resumes booking
2. guest booking -> asks `tell me about the executive suite` -> room details -> `option 2 please` -> resumes booking

## Public ID Continuation

1. guest sends first message with `phone` -> receives `prospect_public_id`
2. guest sends second message with `prospect_public_id` only -> conversation continues

## Completed Booking -> Another Booking

1. guest completes one booking
2. guest says `another booking`
3. fresh booking branch starts
4. prior selected option is not reused
