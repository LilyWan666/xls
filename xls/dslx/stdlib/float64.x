// Copyright 2020 The XLS Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// 64-bit floating point routines.
import apfloat

// TODO(rspringer): Make u32:11 and u32:52 symbolic constants. Currently, such
// constants don't propagate correctly and fail to resolve when in parametric
// specifications.
pub type F64 = apfloat::APFloat<11, 52>;
pub type FloatTag = apfloat::APFloatTag;

pub type TaggedF64 = (FloatTag, F64);

pub fn qnan() -> F64 { apfloat::qnan<u32:11, u32:52>() }
pub fn is_nan(f: F64) -> bool { apfloat::is_nan<u32:11, u32:52>(f) }

pub fn inf(sign: u1) -> F64 { apfloat::inf<u32:11, u32:52>(sign) }
pub fn is_inf(f: F64) -> bool { apfloat::is_inf<u32:11, u32:52>(f) }
pub fn is_pos_inf(f: F64) -> bool { apfloat::is_pos_inf<u32:11, u32:52>(f) }
pub fn is_neg_inf(f: F64) -> bool { apfloat::is_neg_inf<u32:11, u32:52>(f) }

pub fn zero(sign: u1) -> F64 { apfloat::zero<u32:11, u32:52>(sign) }
pub fn one(sign: u1) -> F64 { apfloat::one<u32:11, u32:52>(sign) }

pub fn negate(x: F64) -> F64 { apfloat::negate(x) }

pub fn max_normal_exp() -> s11 { apfloat::max_normal_exp<u32:11>() }
pub fn min_normal_exp() -> s11 { apfloat::min_normal_exp<u32:11>() }

pub fn unbiased_exponent(f: F64) -> s11 {
  apfloat::unbiased_exponent<u32:11, u32:52>(f)
}
pub fn bias(unbiased_exponent_in: s11) -> u11 {
  apfloat::bias<u32:11, u32:52>(unbiased_exponent_in)
}
pub fn flatten(f: F64) -> u64 { apfloat::flatten<u32:11, u32:52>(f) }
pub fn unflatten(f: u64) -> F64 { apfloat::unflatten<u32:11, u32:52>(f) }
pub fn ldexp(f: F64, e : s32) -> F64 {apfloat::ldexp(f, e)}
pub fn cast_from_fixed_using_rne<NUM_SRC_BITS:u32>(s: sN[NUM_SRC_BITS]) -> F64 {
  apfloat::cast_from_fixed_using_rne<u32:11, u32:52>(s)
}
pub fn cast_from_fixed_using_rz<NUM_SRC_BITS:u32>(s: sN[NUM_SRC_BITS]) -> F64 {
  apfloat::cast_from_fixed_using_rz<u32:11, u32:52>(s)
}
pub fn cast_to_fixed<NUM_DST_BITS:u32>(to_cast: F64) -> sN[NUM_DST_BITS] {
  apfloat::cast_to_fixed<NUM_DST_BITS, u32:11, u32:52>(to_cast)
}
pub fn subnormals_to_zero(f: F64) -> F64 {
  apfloat::subnormals_to_zero<u32:11, u32:52>(f)
}

pub fn is_zero_or_subnormal(f: F64) -> bool {
  apfloat::is_zero_or_subnormal<u32:11, u32:52>(f)
}

pub fn eq_2(x: F64, y: F64) -> bool {
  apfloat::eq_2<u32:11, u32:52>(x, y)
}

pub fn gt_2(x: F64, y: F64) -> bool {
  apfloat::gt_2<u32:11, u32:52>(x, y)
}

pub fn gte_2(x: F64, y: F64) -> bool {
  apfloat::gte_2<u32:11, u32:52>(x, y)
}

pub fn lt_2(x: F64, y: F64) -> bool {
  apfloat::lt_2<u32:11, u32:52>(x, y)
}

pub fn lte_2(x: F64, y: F64) -> bool {
  apfloat::lte_2<u32:11, u32:52>(x, y)
}

pub fn normalize(sign:u1, exp: u11, fraction_with_hidden: u53) -> F64 {
  apfloat::normalize<u32:11, u32:52>(sign, exp, fraction_with_hidden)
}

pub fn tag(f: F64) -> FloatTag {
  apfloat::tag<u32:11, u32:52>(f)
}

pub fn to_int<RESULT_SZ: u32>(x: F64) -> sN[RESULT_SZ] {
  apfloat::to_int<u32:11, u32:52, RESULT_SZ>(x)
}

pub fn to_int64(x: F64) -> s64 {
  apfloat::to_int<u32:11, u32:52, u32:64>(x)
}

#[test]
fn normalize_test() {
  let expected = F64 {
      sign: u1:0, bexp: u11:0x2, fraction: u52:0xf_fffe_dcba_0000 };
  let actual = normalize(u1:0, u11:0x12, u53:0x1f_fffe_dcba);
  assert_eq(expected, actual);

  let expected = F64 {
      sign: u1:0, bexp: u11:0x0, fraction: u52:0x0 };
  let actual = normalize(u1:0, u11:0x1, u53:0x0);
  assert_eq(expected, actual);

  let expected = F64 {
      sign: u1:0, bexp: u11:0x0, fraction: u52:0x0 };
  let actual = normalize(u1:0, u11:0xfe, u53:0x0);
  assert_eq(expected, actual);

  let expected = F64 {
      sign: u1:1, bexp: u11:0x4d, fraction: u52:0x0 };
  let actual = normalize(u1:1, u11:0x81, u53:1);
  assert_eq(expected, actual);
  ()
}

#[test]
fn tag_test() {
  assert_eq(tag(F64 { sign: u1:0, bexp: u11:0, fraction: u52:0 }), FloatTag::ZERO);
  assert_eq(tag(F64 { sign: u1:1, bexp: u11:0, fraction: u52:0 }), FloatTag::ZERO);
  assert_eq(tag(zero(u1:0)), FloatTag::ZERO);
  assert_eq(tag(zero(u1:1)), FloatTag::ZERO);

  assert_eq(tag(F64 { sign: u1:0, bexp: u11:0, fraction: u52:1 }), FloatTag::SUBNORMAL);
  assert_eq(tag(F64 { sign: u1:0, bexp: u11:0, fraction: u52:0x7f_ffff }), FloatTag::SUBNORMAL);

  assert_eq(tag(F64 { sign: u1:0, bexp: u11:12, fraction: u52:0 }), FloatTag::NORMAL);
  assert_eq(tag(F64 { sign: u1:1, bexp: u11:u11:0x7fe, fraction: u52:0x7f_ffff }), FloatTag::NORMAL);
  assert_eq(tag(F64 { sign: u1:1, bexp: u11:1, fraction: u52:1 }), FloatTag::NORMAL);

  assert_eq(tag(F64 { sign: u1:0, bexp: u11:0x7ff, fraction: u52:0 }), FloatTag::INFINITY);
  assert_eq(tag(F64 { sign: u1:1, bexp: u11:0x7ff, fraction: u52:0 }), FloatTag::INFINITY);
  assert_eq(tag(inf(u1:0)), FloatTag::INFINITY);
  assert_eq(tag(inf(u1:1)), FloatTag::INFINITY);

  assert_eq(tag(F64 { sign: u1:0, bexp: u11:0x7ff, fraction: u52:1 }), FloatTag::NAN);
  assert_eq(tag(F64 { sign: u1:1, bexp: u11:0x7ff, fraction: u52:0x7f_ffff }), FloatTag::NAN);
  assert_eq(tag(qnan()), FloatTag::NAN);
  ()
}


pub fn add(x: F64, y: F64) -> F64 {
  apfloat::add(x, y)
}

pub fn sub(x: F64, y: F64) -> F64 {
  apfloat::sub(x, y)
}

pub fn mul(x: F64, y: F64) -> F64 {
  apfloat::mul(x, y)
}

pub fn fma(a: F64, b: F64, c: F64) -> F64 {
  apfloat::fma(a, b, c)
}