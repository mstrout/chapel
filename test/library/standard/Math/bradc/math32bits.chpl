use Math;

var x = 0.333: real(32);

var a = acos(x);
writeln("#bits in result = ", numBits(a.type));

var b = acosh(x);
writeln("#bits in result = ", numBits(b.type));

var c = asin(x);
writeln("#bits in result = ", numBits(c.type));

var d = asinh(x);
writeln("#bits in result = ", numBits(d.type));

var e = atan(x);
writeln("#bits in result = ", numBits(e.type));

var f = atan2(x, x);
writeln("#bits in result = ", numBits(f.type));

var g = atanh(x);
writeln("#bits in result = ", numBits(g.type));

var h = cbrt(x);
writeln("#bits in result = ", numBits(h.type));

var i = ceil(x);
writeln("#bits in result = ", numBits(i.type));

var j = cos(x);
writeln("#bits in result = ", numBits(j.type));

var k = cosh(x);
writeln("#bits in result = ", numBits(k.type));

var l = erf(x);
writeln("#bits in result = ", numBits(l.type));

var m = erfc(x);
writeln("#bits in result = ", numBits(m.type));

var n = exp(x);
writeln("#bits in result = ", numBits(n.type));

var p = expm1(x);
writeln("#bits in result = ", numBits(p.type));

var q = abs(x);
writeln("#bits in result = ", numBits(q.type));

var r = floor(x);
writeln("#bits in result = ", numBits(r.type));

var s = lnGamma(x);
writeln("#bits in result = ", numBits(s.type));

var t = log(x);
writeln("#bits in result = ", numBits(t.type));

var v = log10(x);
writeln("#bits in result = ", numBits(v.type));

var w = log1p(x);
writeln("#bits in result = ", numBits(w.type));

var z = rint(x);
writeln("#bits in result = ", numBits(z.type));

var bb = sin(x);
writeln("#bits in result = ", numBits(bb.type));

var cc = sinh(x);
writeln("#bits in result = ", numBits(cc.type));

var dd = sqrt(x);
writeln("#bits in result = ", numBits(dd.type));

var ee = tan(x);
writeln("#bits in result = ", numBits(ee.type));

var ff = tanh(x);
writeln("#bits in result = ", numBits(ff.type));
