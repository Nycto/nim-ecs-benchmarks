
type
  Position* = object
    x*, y*: float32

  Velocity* = object
    x*, y*: float32

  Acceleration* = object
    x*, y*: float32

  Heal* = object
    hp*: int

  Rotation* = object
    angle*: float32

  Scale* = object
    sx*, sy*: float32

  Mass* = object
    value*: float32

  Friction* = object
    coeff*: float32

  Bounce* = object
    factor*: float32

  Lifetime* = object
    remaining*: float32

  Energy* = object
    value*: float32

  Force* = object
    fx*, fy*: float32

  Torque* = object
    value*: float32
