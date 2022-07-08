##  Copyright 2022 Myrl Marmarelis
##
##  Licensed under the Apache License, Version 2.0 (the "License");
##  you may not use this file except in compliance with the License.
##  You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
##  Unless required by applicable law or agreed to in writing, software
##  distributed under the License is distributed on an "AS IS" BASIS,
##  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##  See the License for the specific language governing permissions and
##  limitations under the License.

using Serialization

# fully transparent mechanics --- no macro magic necessary
patch_type(T::DataType) = T # return same type by default

# this function has remained the same in Julia's stdlib within versions 1.6--1.8, at least.
function Serialization.deserialize(s::AbstractSerializer, t::DataType)
  nf = length(u.types)
  u = patch_type(t)
  if nf == 0 && t.size > 0
    # bits type
    return convert(t, read(s.io, u))
  elseif ismutabletype(t)
    x = ccall(:jl_new_struct_uninit, Any, (Any,), t)
    y = ccall(:jl_new_struct_uninit, Any, (Any,), u)
    # is this for children cyclically referring to the same heap object?
    deserialize_cycle(s, x)
    for i in 1:nf
      tag = Int32(read(s.io, UInt8)::UInt8)
      if tag != UNDEFREF_TAG
        ccall(:jl_set_nth_field, Cvoid, (Any, Csize_t, Any),
          y, i-1, handle_deserialize(s, tag))
      end
    end
    z = convert(t, y) # now copy contents to x
    for i in 1:length(t.types)
      ccall(:jl_set_nth_field, Cvoid, (Any, Csize_t, Any),
        x, i-1, getfield(z, i))
    end
    return x
  elseif nf == 0
    return convert(t, # `|> t` looks better though
      ccall(:jl_new_struct_uninit, Any, (Any,), u) )
  else
    na = nf
    vflds = Vector{Any}(undef, nf)
    for i in 1:nf
      tag = Int32(read(s.io, UInt8)::UInt8)
      if tag != UNDEFREF_TAG
        f = handle_deserialize(s, tag)
        na >= i && (vflds[i] = f)
      else
        na >= i && (na = i - 1) # rest of tail must be undefined values
      end
    end
    return convert(t,
      ccall(:jl_new_structv, Any, (Any, Ptr{Any}, UInt32), u, vflds, na) )
  end
end