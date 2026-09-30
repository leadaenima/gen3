-- Minimal 4x4 matrix math for voxel world mode.
--
-- Row-major, and sent to the shader with shader:send("mvp", "row", m).
-- LOVE 11.5's matrix uniform defaults to column-major, so the "row" layout
-- argument is what lets these tables read the same way they are written
-- here -- translation in the fourth column, m[4]/m[8]/m[12].
--
-- Only what the renderer actually needs: a perspective projection (the
-- camera), an orthographic one (the sun's shadow pass), an asymmetric one
-- (a headset's per-eye frustum), a look-based view, a quaternion rotation
-- (a headset's pose), and the translate/rotateY/scale a model matrix is
-- built from. No general inverse -- the VR view inverts its rigid pieces
-- one at a time.

local Mat4 = {}

function Mat4.identity()
  return { 1, 0, 0, 0,
           0, 1, 0, 0,
           0, 0, 1, 0,
           0, 0, 0, 1 }
end

-- a * b, both row-major. `mul` allocates; `mulInto` writes `out`.
local MUL_TMP = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }

local function mulWrite(out, a, b)
  local a1, a2, a3, a4 = a[1], a[2], a[3], a[4]
  local a5, a6, a7, a8 = a[5], a[6], a[7], a[8]
  local a9, a10, a11, a12 = a[9], a[10], a[11], a[12]
  local a13, a14, a15, a16 = a[13], a[14], a[15], a[16]
  local b1, b2, b3, b4 = b[1], b[2], b[3], b[4]
  local b5, b6, b7, b8 = b[5], b[6], b[7], b[8]
  local b9, b10, b11, b12 = b[9], b[10], b[11], b[12]
  local b13, b14, b15, b16 = b[13], b[14], b[15], b[16]
  out[1]  = a1 * b1 + a2 * b5 + a3 * b9  + a4 * b13
  out[2]  = a1 * b2 + a2 * b6 + a3 * b10 + a4 * b14
  out[3]  = a1 * b3 + a2 * b7 + a3 * b11 + a4 * b15
  out[4]  = a1 * b4 + a2 * b8 + a3 * b12 + a4 * b16
  out[5]  = a5 * b1 + a6 * b5 + a7 * b9  + a8 * b13
  out[6]  = a5 * b2 + a6 * b6 + a7 * b10 + a8 * b14
  out[7]  = a5 * b3 + a6 * b7 + a7 * b11 + a8 * b15
  out[8]  = a5 * b4 + a6 * b8 + a7 * b12 + a8 * b16
  out[9]  = a9 * b1 + a10 * b5 + a11 * b9  + a12 * b13
  out[10] = a9 * b2 + a10 * b6 + a11 * b10 + a12 * b14
  out[11] = a9 * b3 + a10 * b7 + a11 * b11 + a12 * b15
  out[12] = a9 * b4 + a10 * b8 + a11 * b12 + a12 * b16
  out[13] = a13 * b1 + a14 * b5 + a15 * b9  + a16 * b13
  out[14] = a13 * b2 + a14 * b6 + a15 * b10 + a16 * b14
  out[15] = a13 * b3 + a14 * b7 + a15 * b11 + a16 * b15
  out[16] = a13 * b4 + a14 * b8 + a15 * b12 + a16 * b16
end

function Mat4.mulInto(out, a, b)
  if type(out) ~= "table" then out = {} end
  if out == a or out == b then
    mulWrite(MUL_TMP, a, b)
    local i = 1
    while i <= 16 do
      out[i] = MUL_TMP[i]
      i = i + 1
    end
    return out
  end
  mulWrite(out, a, b)
  return out
end

function Mat4.mul(a, b)
  return Mat4.mulInto({}, a, b)
end

function Mat4.translate(x, y, z)
  return { 1, 0, 0, x,
           0, 1, 0, y,
           0, 0, 1, z,
           0, 0, 0, 1 }
end

-- Fill `out` (or a new table) with a translation. Neighbor draws used to
-- allocate a fresh 4x4 on every mesh, every pass, every frame.
function Mat4.translateInto(out, x, y, z)
  if type(out) ~= "table" then
    return Mat4.translate(x, y, z)
  end
  out[1],  out[2],  out[3],  out[4]  = 1, 0, 0, x
  out[5],  out[6],  out[7],  out[8]  = 0, 1, 0, y
  out[9],  out[10], out[11], out[12] = 0, 0, 1, z
  out[13], out[14], out[15], out[16] = 0, 0, 0, 1
  return out
end

function Mat4.scale(x, y, z)
  return { x, 0, 0, 0,
           0, y, 0, 0,
           0, 0, z, 0,
           0, 0, 0, 1 }
end

function Mat4.scaleInto(out, x, y, z)
  if type(out) ~= "table" then
    return Mat4.scale(x, y, z)
  end
  out[1],  out[2],  out[3],  out[4]  = x, 0, 0, 0
  out[5],  out[6],  out[7],  out[8]  = 0, y, 0, 0
  out[9],  out[10], out[11], out[12] = 0, 0, z, 0
  out[13], out[14], out[15], out[16] = 0, 0, 0, 1
  return out
end

function Mat4.rotateYInto(out, a)
  local c, s = math.cos(a), math.sin(a)
  if type(out) ~= "table" then out = {} end
  out[1],  out[2],  out[3],  out[4]  =  c, 0, s, 0
  out[5],  out[6],  out[7],  out[8]  =  0, 1, 0, 0
  out[9],  out[10], out[11], out[12] = -s, 0, c, 0
  out[13], out[14], out[15], out[16] =  0, 0, 0, 1
  return out
end

function Mat4.rotateY(a)
  return Mat4.rotateYInto({}, a)
end

function Mat4.rotateXInto(out, a)
  local c, s = math.cos(a), math.sin(a)
  if type(out) ~= "table" then out = {} end
  out[1],  out[2],  out[3],  out[4]  = 1,  0,  0, 0
  out[5],  out[6],  out[7],  out[8]  = 0,  c, -s, 0
  out[9],  out[10], out[11], out[12] = 0,  s,  c, 0
  out[13], out[14], out[15], out[16] = 0,  0,  0, 1
  return out
end

function Mat4.rotateX(a)
  return Mat4.rotateXInto({}, a)
end

-- The rotation a unit quaternion describes, row-major. The VR rig is what
-- needs it: an OpenXR eye pose arrives as position + orientation
-- quaternion, and both the eye's transform and its inverse (the view) are
-- built from this.
function Mat4.fromQuatInto(out, x, y, z, w)
  if type(out) ~= "table" then out = {} end
  local xx, yy, zz = x * x, y * y, z * z
  local xy, xz, yz = x * y, x * z, y * z
  local wx, wy, wz = w * x, w * y, w * z
  out[1],  out[2],  out[3],  out[4]  = 1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy), 0
  out[5],  out[6],  out[7],  out[8]  = 2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx), 0
  out[9],  out[10], out[11], out[12] = 2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy), 0
  out[13], out[14], out[15], out[16] = 0, 0, 0, 1
  return out
end

function Mat4.fromQuat(x, y, z, w)
  return Mat4.fromQuatInto({}, x, y, z, w)
end

-- Transpose. For a pure rotation this IS the inverse, which is how the VR
-- view matrix is assembled without a general 4x4 inverse.
local TRANSPOSE_TMP = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }

function Mat4.transposeInto(out, m)
  if type(out) ~= "table" then out = {} end
  local src = m
  if out == m then
    local i = 1
    while i <= 16 do
      TRANSPOSE_TMP[i] = m[i]
      i = i + 1
    end
    src = TRANSPOSE_TMP
  end
  out[1],  out[2],  out[3],  out[4]  = src[1], src[5], src[9],  src[13]
  out[5],  out[6],  out[7],  out[8]  = src[2], src[6], src[10], src[14]
  out[9],  out[10], out[11], out[12] = src[3], src[7], src[11], src[15]
  out[13], out[14], out[15], out[16] = src[4], src[8], src[12], src[16]
  return out
end

function Mat4.transpose(m)
  return Mat4.transposeInto({}, m)
end

-- Right-handed perspective from an OpenXR-style asymmetric field of view:
-- four signed HALF-ANGLES off the view axis (left and down negative), onto
-- GL clip space (z in [-1, 1]). A headset's per-eye frustum is off-centre
-- -- the nose side is narrower than the temple side -- so the symmetric
-- perspective() above cannot express it.
function Mat4.fovProjectionInto(out, angleLeft, angleRight, angleUp, angleDown,
                                near, far)
  if type(out) ~= "table" then out = {} end
  local l, r = math.tan(angleLeft), math.tan(angleRight)
  local u, d = math.tan(angleUp), math.tan(angleDown)
  local w, h, dz = r - l, u - d, near - far
  out[1],  out[2],  out[3],  out[4]  = 2 / w, 0, (r + l) / w, 0
  out[5],  out[6],  out[7],  out[8]  = 0, 2 / h, (u + d) / h, 0
  out[9],  out[10], out[11], out[12] = 0, 0, (far + near) / dz, (2 * far * near) / dz
  out[13], out[14], out[15], out[16] = 0, 0, -1, 0
  return out
end

function Mat4.fovProjection(angleLeft, angleRight, angleUp, angleDown,
                            near, far)
  return Mat4.fovProjectionInto({}, angleLeft, angleRight, angleUp, angleDown,
                                near, far)
end

-- Right-handed perspective onto GL clip space (z in [-1, 1]).
function Mat4.perspective(fovY, aspect, near, far)
  local f = 1 / math.tan(fovY / 2)
  local d = near - far
  return { f / aspect, 0, 0, 0,
           0, f, 0, 0,
           0, 0, (far + near) / d, (2 * far * near) / d,
           0, 0, -1, 0 }
end

function Mat4.perspectiveInto(out, fovY, aspect, near, far)
  local f = 1 / math.tan(fovY / 2)
  local d = near - far
  if type(out) ~= "table" then out = {} end
  out[1],  out[2],  out[3],  out[4]  = f / aspect, 0, 0, 0
  out[5],  out[6],  out[7],  out[8]  = 0, f, 0, 0
  out[9],  out[10], out[11], out[12] = 0, 0, (far + near) / d, (2 * far * near) / d
  out[13], out[14], out[15], out[16] = 0, 0, -1, 0
  return out
end

-- Right-handed orthographic projection onto GL clip space (z in [-1, 1]).
-- The view-space box is x in [l, r], y in [b, t], z in [-f, -n] -- near and
-- far are DISTANCES down the view's -z, exactly as in perspective() above.
-- Parallel, so a sun is a direction and nothing else: no eye point, no
-- foreshortening, and clip z stays linear in world units, which is what
-- lets the shadow pass store depth as a plain number.
function Mat4.ortho(l, r, b, t, n, f)
  local out = {}
  return Mat4.orthoInto(out, l, r, b, t, n, f)
end

function Mat4.orthoInto(out, l, r, b, t, n, f)
  if type(out) ~= "table" then out = {} end
  out[1],  out[2],  out[3],  out[4]  = 2 / (r - l), 0, 0, -(r + l) / (r - l)
  out[5],  out[6],  out[7],  out[8]  = 0, 2 / (t - b), 0, -(t + b) / (t - b)
  out[9],  out[10], out[11], out[12] = 0, 0, -2 / (f - n), -(f + n) / (f - n)
  out[13], out[14], out[15], out[16] = 0, 0, 0, 1
  return out
end

-- Right-handed look-at. eye/target/up are {x, y, z}.
-- Nested closures and per-call vector tables used to land here every
-- voxel frame (orbit, first person, battle, each VR eye).
function Mat4.lookAtInto(out, eye, target, up)
  if type(out) ~= "table" then out = {} end
  local fx = target[1] - eye[1]
  local fy = target[2] - eye[2]
  local fz = target[3] - eye[3]
  local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
  if fl == 0 then
    fx, fy, fz = 0, 0, 0
  else
    fx, fy, fz = fx / fl, fy / fl, fz / fl
  end
  local sx = fy * up[3] - fz * up[2]
  local sy = fz * up[1] - fx * up[3]
  local sz = fx * up[2] - fy * up[1]
  local sl = math.sqrt(sx * sx + sy * sy + sz * sz)
  if sl == 0 then
    sx, sy, sz = 0, 0, 0
  else
    sx, sy, sz = sx / sl, sy / sl, sz / sl
  end
  -- true up is cross(s, f) and is NOT re-normalised, matching lookAt().
  local ux = sy * fz - sz * fy
  local uy = sz * fx - sx * fz
  local uz = sx * fy - sy * fx
  out[1],  out[2],  out[3],  out[4]  =  sx,  sy,  sz, -(sx * eye[1] + sy * eye[2] + sz * eye[3])
  out[5],  out[6],  out[7],  out[8]  =  ux,  uy,  uz, -(ux * eye[1] + uy * eye[2] + uz * eye[3])
  out[9],  out[10], out[11], out[12] = -fx, -fy, -fz,   (fx * eye[1] + fy * eye[2] + fz * eye[3])
  out[13], out[14], out[15], out[16] =   0,   0,   0,  1
  return out
end

function Mat4.lookAt(eye, target, up)
  return Mat4.lookAtInto({}, eye, target, up)
end

return Mat4
