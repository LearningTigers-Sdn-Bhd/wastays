`ws-doodle-bg.png` is the pattern behind the guest chat thread.

It is used as a **mask**, not as a picture: the chat reads it for its shape and
paints its own colour through it. That is why a doodle drawn in white ink for a
dark app works here on a cream one -- and why replacing it does not mean
matching any particular colour. Only two things matter:

- **Tileable.** It repeats; a visible seam becomes a grid of seams.
- **Alpha carries the drawing.** Ink colour is ignored entirely.

To change how it looks, edit the three variables on `.public-chat` in
`app/assets/tailwind/public/chat.css` -- ink, strength, tile size. Not the file.

`--public-chat-doodle-strength` has a ceiling of about 0.15, and it is not a
matter of taste: the author labels sit on this surface, and past that they fall
under 4.5:1. The note above the variables has the arithmetic.

Removing the file is a supported state. The chat looks it up by name and renders
a plain thread when it is not there, rather than failing.
