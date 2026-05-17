### Does dual camera access back + front work?
Different logical sensors on _Pixel 9_, so yeah.

### Does dual camera access on 2 back lenses work?
No, the only concurrently supported pair on _Pixel 9_ is logical back (0) and logical front (1).

The three physical back sensors (2, 3, 4) all share the same ISP pipeline and can't be opened simultaneously.
This is a hardware limitation.
The logical camera (0) can switch between the physical lenses internally, but they can't be accessed in parallel by an app.