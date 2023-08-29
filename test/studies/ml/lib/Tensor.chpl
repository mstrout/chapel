module Tensor {

    import Math;
    import IO;
    import IO.FormattedIO;
    import ChapelArray;
    import Random;
    import AutoMath;

    param debugPrint = false;

    // var rng = new IainsRNG(5); 
    var rng = new Random.NPBRandom.NPBRandomStream(eltType=real(64),seed=5);
    
    proc seedRandom(seed) {
        // rng = new IainsRNG(seed);
        rng = new Random.NPBRandom.NPBRandomStream(eltType=real(64),seed=5);
        // rng = new IainsRNG(5);
    }

    proc err(args...?n) {
        var s = "";
        for param i in 0..<n {
            s += args(i): string;
        }
        try! throw new Error(s);
    }
    proc debugWrite(args...?n) {
        if debugPrint {
            var s = "";
            for param i in 0..<n {
                s += args(i): string;
            }
            try! IO.stdout.write(s);
            try! IO.stdout.flush();
        }
    }

    iter cartesian(X,Y) {
        for x in X {
            for y in Y {
                yield (x,y);
            }
        }
    }
    iter cartesian(param tag: iterKind,X,Y) where tag == iterKind.standalone {
        forall x in X {
            forall y in Y {
                yield (x,y);
            }
        }
    }

    proc emptyDomain(param rank: int): domain(rank,int) {
        var d: rank*range;
        for r in d do r = 0..#0;
        return {(...d)};
    }

    proc domainFromShape(shape: int ...?d): domain(d,int) {
        var ranges: d*range;
        for (size,r) in zip(shape,ranges) do r = 0..#size;
        return {(...ranges)};
    }

    // Returns the nth element in a domain of shape `bounds`. Arbitrary mixed base counter.
    proc nbase(bounds: ?rank*int, n: int): rank*int {
        var filled: rank*int;
        var idx: int = rank - 1;
        var curr: int = 0;
        var carry: bool = false;
        while curr < n {
            filled[idx] += 1;
            if filled[idx] >= bounds[idx] {
                carry = true;
                filled[idx] = 0;
                idx -= 1;
                if idx < 0 then err("Error in nbase: ", n," is too large for bounds.");
            } else {
                carry = false;
                idx = rank - 1;
                curr += 1;
            }
        }
        return filled;
    }

    proc indexInShape(shape: ?rank*int, in n: int): rank*int {
        var idxs: rank*int;
        const size = * reduce shape;
        if n > size then err("Error in indexInShape: ", n," is too large for shape.");
        for param i in 0..#rank {
            const dim = shape[rank - i - 1];
            idxs[rank - i - 1] = n % dim;
            n = Math.divfloor(n,dim);
        }
        return idxs;
    }

    record Tensor {
        param rank: int;
        type eltType = real(64);

        var _domain: domain(rank,int);
        var data: [_domain] eltType;

        proc shape do return this._domain.shape;
        proc _dom do return this._domain;

        forwarding data only this;
        forwarding data only these;

        proc reshapeDomain(d: this._domain.type) {
            this._domain = d;
            var D = this.data.domain;
            D = d;
        }

        proc init(param rank: int, type eltType) {
            this.rank = rank;
            this.eltType = eltType;
            var ranges: rank*range;
            for r in ranges do r = 0..#0;
            this._domain = {(...ranges)};
        }
        proc init(type eltType, shape: int ...?dim) {
            this.init(rank=dim,eltType=eltType);
            this.reshapeDomain(domainFromShape((...shape)));
        }
        proc init(shape: int ...?dim) {
            this.init(rank=dim,eltType=real);
            this.reshapeDomain(domainFromShape((...shape)));
        }
        proc init(data: [?d] ?eltType) {
            this.rank = d.rank;
            this.eltType = eltType;
            this._domain = d;
            this.data = data;
        }
        proc init(dom: ?d) where isDomainType(d) {
            this.rank = dom.rank;
            this.eltType = real;
            this._domain = dom;
        }
        proc init(itr) where itr.type:string == "promoted expression" || itr.type:string == "iterator" {
            const A = itr;
            this.init(A);
            writeln("init(iter)");
        }

        proc init=(other: Tensor(?rank,?eltType)) {
            this.rank = other.rank;
            this.eltType = other.eltType;
            this._domain = other._domain;
            this.data = other.data;
        }

        operator =(ref lhs: Tensor(?rank,?eltType), rhs: Tensor(rank,eltType)) {
            lhs._domain = rhs._domain;
            lhs.data = rhs.data;
        }

        operator =(ref lhs: Tensor(?rank,?eltType), rhs: [?d] eltType) where d.rank == rank {
            lhs._domain = d;
            lhs.data = rhs;
        }

        proc init=(rhs: [?d] eltType) where d.rank == rank {
            this.init(d.rank,eltType);
            this.reshapeDomain(d);
            this.data = rhs;
        }

        operator :(from: [?d] ?eltType, type toType: Tensor(d.rank,eltType)) {
            var t: Tensor(d.rank,eltType) = from;
            return t;
        }
        
        // Wasnt sure what to do with these
        // operator =(ref lhs: Tensor(?rank,?eltType), in rhs: ?it) where (isRefIterType(it) || (isArray(rhs) && rhs.eltType == eltType)) && rhs.rank == rank {
        //     lhs.reshapeDomain(rhs.domain);
        //     lhs.data = rhs;
        // }
        // proc init=(in rhs: ?it) where isRefIterType(it) || isArray(rhs) {
        //     this.init(rank,eltType);
        //     this.reshapeDomain(rhs.domain);
        //     this.data = rhs;
        // }
        // operator :(in from: ?it, type toType: Tensor(?rank,?eltType)) where (isRefIterType(it) || (isArray(from) && from.eltType == eltType)) && from.rank == rank {
        //     // compilerError("Cannot convert from ",from.type:string," to ",toType:string);
        //     var t: Tensor(rank,eltType) = from;
        //     return t;
        // }

        operator =(ref lhs: Tensor(?rank,?eltType), itr) where itr.type:string == "promoted expression" || itr.type:string == "iterator" {
            lhs.reshapeDomain(itr.domain);
            lhs.data = itr;
        }

        proc init=(itr) where itr.type:string == "promoted expression" || itr.type:string == "iterator" {
            const A = itr;
            this.init(A);
        }

        operator :(itr, type toType: Tensor(?rank,?eltType)) where itr.type:string == "promoted expression" || itr.type:string == "iterator" {
            var t: Tensor(rank,eltType) = itr;
            return t;
        }


        // Transposes a vector to a row matrix
        proc transpose() where rank == 1 {
            const (p,) = shape;
            var t = new Tensor(eltType,1,p);
            t.data[0,..] = this.data;
            return t;
        }

        // Matrix transpose
        proc transpose() where rank == 2 {
            const (m,n) = this.shape;
            var M = new Tensor(2,eltType);
            M.reshapeDomain({0..#n,0..#m});
            forall (i,j) in M.domain with (ref M, ref this) {
                M.data[i,j] = this.data[j,i];
            }
            return M;
        }

        // Normalizes the tensor to have unit frobenius norm
        proc normalize() {
            const norm = sqrt(frobeniusNormPowTwo(this));
            const data = this.data / norm;
            return new Tensor(data);
        }

        // Retruns new tensor with provided domain
        proc reshape(dom_) {
            const dom = domainFromShape((...dom_.shape));
            var t = new Tensor(dom.rank,eltType);
            t.reshapeDomain(dom);
            t.data = for (i,a) in zip(t.domain,this.data) do a;
            return t;
        }

        // Returns new tensor with provided shape
        proc reshape(shape: int ...?d) {
            const dom = domainFromShape((...shape));
            return this.reshape(dom);            
        }

        // Returns new tensor with rank 1
        proc flatten() {
            const size = this.data.domain.size;
            return this.reshape({0..#size});
        }
        proc degen() {this.degen("");}
        proc degen(s... ?k) {
            for i in this.domain {
                const x = this[i];
                if AutoMath.isnan(x) {
                    writeln(this,(...s));
                    err("NaN in tensor.");
                }
                if AutoMath.isinf(x) {
                    writeln(this,(...s));
                    err("Inf in tensor.");
                }
            }
        }

        // Returns a tensor with argument function applied to each element
        proc fmap(fn) {
            var t = new Tensor(rank,eltType);
            t.reshapeDomain(this.domain);
            t.data = fn(this.data);
            return t;
        }
        
        // Prints the tensor (only really works for rank 1 and 2)
        proc writeThis(fw: IO.fileWriter) throws {
            fw.write("tensor(");
            const shape = this.shape;
            var first: bool = true;
            for (x,i) in zip(data,0..) {
                const idx = nbase(shape,i);
                if idx[rank - 1] == 0 {
                    if !first {
                        fw.write("\n       ");
                    }
                    fw.write("[");
                }
                fw.writef("%{##.##########}",x);
                
                if idx[rank - 1] < shape[rank - 1] - 1 {
                    if rank == 1 then
                        fw.write("\n        ");
                    else
                        fw.write("  ");
                } else {
                    fw.write("]");
                }
                first = false;
            }
            fw.writeln(", shape=",this.shape,")");
        }

        // Serializer for tensor: rank,...shape,...data
        proc write(fw: IO.fileWriter) throws {
            fw.write(rank);
            for s in shape do
                fw.write(s:int);
            for i in data.domain do
                fw.write(data[i]);
        }

        // Deserializer for tensor: rank,...shape,...data
        proc read(fr: IO.fileReader) throws {
            var r = fr.read(int);
            if r != rank then
                err("Error reading tensor: rank mismatch.", r , " != this." , rank);
            var s = this.shape;
            for i in 0..#rank do
                s[i] = fr.read(int);
            var d = domainFromShape((...s));
            this._domain = d;
            for i in d do
                this.data[i] = fr.read(eltType);
        }
    }
    
    inline proc SumReduceScanOp.accumulate(x: Tensor(?)) {
        if this.value.domain.size == 0 then this.value.reshapeDomain(x.domain);
        this.value += x;
    }
    inline proc SumReduceScanOp.combine(x: SumReduceScanOp(Tensor(?))) {
        if this.value.domain.size == 0 then this.value.reshapeDomain(x.value.domain);
        this.value += x.value;
    }
    inline proc SumReduceScanOp.accumulateOntoState(ref state: Tensor(?d), x: Tensor(d)) {
        if state.domain.size == 0 then state.reshapeDomain(x.domain);
        state += x;
    }

    operator +(lhs: Tensor(?rank,?eltType), rhs: Tensor(rank,eltType)) {
        var t = new Tensor(rank=rank,eltType=eltType);


        // t.reshapeDomain(lhs.domain); // fixme. should be union.
        if lhs.domain.size != rhs.domain.size then
            err("Cannot add tensors of different sizes. + ", lhs.domain.size, " != ", rhs.domain.size,"  [",lhs.shape," + ",rhs.shape,"]");
        t.reshapeDomain(lhs.domain);
        t.data = lhs.data + rhs.data;
        return t;


        // if lhs.domain.size == rhs.domain.size {
        //     t.reshapeDomain(lhs.domain); // fixme. should be union.
        //     t.data = lhs.data + rhs.data;
        //     return t;
        // } else {
        //     err("Cannot add tensors of different sizes. + ");
        // }

        if lhs.domain.size < rhs.domain.size {
            t.reshapeDomain(rhs.domain);
            t.data = rhs.data;
        } else if rhs.domain.size < lhs.domain.size {
            t.reshapeDomain(lhs.domain);
            t.data = lhs.data;
        } else if lhs.domain.size == rhs.domain.size {
            t.reshapeDomain(lhs.domain); // fixme. should be union.
            t.data = lhs.data + rhs.data;
        } else {
            halt("I don't know what to do here.");
        }
        return t;
    }
    operator +=(ref lhs: Tensor(?d), const ref rhs: Tensor(d)) {
        if lhs.domain.size == rhs.domain.size {
            lhs.data += rhs.data;
        } 
        else if lhs.domain.size == 0 && rhs.domain.size != 0 {
            lhs.reshapeDomain(rhs.domain);
            lhs.data = rhs.data;
        }
        else if lhs.domain.size != 0 && rhs.domain.size == 0 {
            // do nothing
        }
        // if lhs.domain.size == 0 && rhs.domain.size != 0 {
        //     lhs.reshapeDomain(rhs.domain);
        //     lhs.data = rhs.data;
        // } 
        else {
            // lhs.data += (lhs + rhs).data;
            err("Cannot add tensors of different sizes. += ", lhs.domain.size, " != ", rhs.domain.size,"  [",lhs.shape," += ",rhs.shape,"]");
        }
    }
    operator +=(ref lhs: Tensor(?rank,?eltType), rhs) where (isArray(rhs) && rhs.rank == rank) || rhs.type == eltType {
        lhs.data += rhs;
    }
    operator +=(ref lhs: Tensor(?rank,?eltType), rhs) where rhs.type:string == "promoted expression" || rhs.type:string == "iterator" {
        lhs.data += rhs;
    }
    operator -(lhs: Tensor(?rank,?eltType), rhs: Tensor(rank,eltType)) {
        var t = new Tensor(rank=rank,eltType=eltType);
        t.reshapeDomain(lhs._domain);
        t.data = lhs.data - rhs.data;
        return t;
    }
    operator -=(ref lhs: Tensor(?d), const ref rhs: Tensor(d)) {
        lhs.data -= rhs.data;
    }
    operator -=(ref lhs: Tensor(?rank,?eltType), rhs) where (isArray(rhs) && rhs.rank == rank) || rhs.type == eltType {
        lhs.data -= rhs;
    }
    operator *(c: ?eltType, rhs: Tensor(?rank,eltType)) {
        var t = new Tensor(rank=rank,eltType=eltType);
        t.reshapeDomain(rhs._domain);
        t.data = c * rhs.data;
        return t;
    }
    operator *(lhs: Tensor(?rank,?eltType), c: eltType) {
        var t = new Tensor(rank=rank,eltType=eltType);
        t.reshapeDomain(lhs._domain);
        t.data = lhs.data * c;
        return t;
    }
    operator *(lhs: Tensor(?rank,?eltType), rhs: Tensor(rank,eltType)) {
        // Hermitian product, not composition
        var t = new Tensor(rank=rank,eltType=eltType);
        t.reshapeDomain(lhs._domain);
        t.data = lhs.data * rhs.data;
        return t;
    }
    operator *=(ref lhs: Tensor(?d), const ref rhs: Tensor(d)) {
        lhs.data *= rhs.data;
    }
    operator *=(ref lhs: Tensor(?rank,?eltType), rhs) where (isArray(rhs) && rhs.rank == rank) || rhs.type == eltType {
        lhs.data *= rhs;
    }

    // Matrix-vector multiplication
    operator *(lhs: Tensor(2,?eltType), rhs: Tensor(1,eltType)): Tensor(1,eltType) {
        const (m,n) = lhs.shape;
        const (p,) = rhs.shape;
        if n != p then
            err("Trying to apply a matrix of shape ",lhs.shape, " to a vector of shape ", rhs.shape);

        const a = lhs.data;
        const v = rhs.data;
        var w = new Tensor(rank=1,eltType=eltType);
        w.reshapeDomain({0..#m});
        forall i in 0..#m with (ref w) {
            const row = a[i,..];
            w[i] = + reduce (row * v);
        }
        return w;
    }

    // Vector-row-matrix multiplication. Fills out multiplication table between a vector and a transposed vector
    operator *(lhs: Tensor(1,?eltType), rhs: Tensor(2,eltType)): Tensor(2,eltType) {
        const (p,) = lhs.shape;
        const (m,n) = rhs.shape;
        if m != 1 then
            err("Trying to apply a vector of shape ",lhs.shape, " to a matrix of shape ", rhs.shape, ". m needs to be 1");
        
        var b = new Tensor(rank=2,eltType=eltType);
        b.reshapeDomain({0..#p, 0..#n});
        foreach (i,j) in {0..#p, 0..#n} {
            b[i,j] = lhs[i] * rhs[0,j];
        }
        return b; 
    }

    // Matrix-matrix multiplication
    operator *(lhs: Tensor(2,?eltType), rhs: Tensor(2,eltType)): Tensor(2,eltType) {
        const (m,n) = lhs.shape;
        const (p,q) = rhs.shape;
        if n != p then
            err("Trying to apply a matrix of shape ",lhs.shape, " to a matrix of shape ", rhs.shape);

        const a = lhs.data;
        const b = rhs.data;
        var c = new Tensor(rank=2,eltType=eltType);
        c.reshapeDomain({0..#m, 0..#q});
        forall (i,j) in c.domain with (ref c) {
            const row = a[i,..];
            const col = b[..,j];
            c[i,j] = + reduce (row * col);
        }
        return c;
    }

    operator /(lhs: Tensor(?d,?eltType), c: eltType) {
        const data = lhs.data / c;
        return new Tensor(data);
    }
    operator -(lhs: Tensor(?d,?eltType), c: eltType) {
        const data = lhs.data - c;
        return new Tensor(data);
    }

    // Sigmoid function
    proc _sigmoid(x: real): real {
        return 1.0 / (1.0 + Math.exp(-x));
    }
    // Derivative of sigmoid function
    proc _sigmoidPrime(x: real): real {
        const s = _sigmoid(x);
        return s * (1.0 - s);
    }

    // Apply sigmoid function to each element of tensor
    proc sigmoid(t: Tensor(?d)): Tensor(d) {
        return t.fmap(_sigmoid);
    }

    // Apply derivative of sigmoid function to each element of tensor
    proc sigmoidPrime(t: Tensor(?d)): Tensor(d) {
        return t.fmap(_sigmoidPrime);
    }

    // Get forbenius norm before sqrt
    proc frobeniusNormPowTwo(t: Tensor(?d)): real {
        const AA = t.data ** 2.0;
        return + reduce AA;
    }

    // Apply exponential function to each element of tensor
    proc exp(t: Tensor(?d)): Tensor(d) {
        var y = new Tensor(t.domain);
        foreach i in t.domain do
            y.data[i] = Math.exp(t.data[i]);
        return y;
    }

    // Wikipedia implementation (helper for randn)
    // mu : mean
    // sigma : standard deviation
    proc boxMuller(mu: real, sigma: real) {
        var u1 = rng.getNext();
        var u2 = rng.getNext();
        var z0 = sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math.pi * u2);
        return mu + (sigma * z0);
    }
    proc normal() {
        return boxMuller(0.0,1.0);
    }

    // Initialize a tensor with random values from a normal distribution
    proc randn(shape: int ...?d): Tensor(d,real) {
        var t = new Tensor((...shape));
        for i in t.domain {
            t.data[i] = normal();
        }
        return t;
    }

    // Initialize a tensor with random values from a normal distribution
    proc randn(shape: int ...?d, mu: real, sigma: real): Tensor(d,real) {
        var t = new Tensor((...shape));
        var m: [t.data.domain] real;
        for i in m.domain {
            var x: real = boxMuller(mu,sigma);
            m[i] = x;
        }
        return new Tensor(m);
    }

    // Initialize a tensor with zero values
    proc zeros(shape: int ...?d): Tensor(d,real) {
        return new Tensor((...shape));
    }

    // Shuffle a tensor in place
    proc shuffle(ref x) {
        Random.shuffle(x,seed=(rng.getNext() * 10):int);
    }

    // Get the max value index in an array
    proc argmax(A: [?d] real) where d.rank == 1 {
        var am: int = 0;
        for i in A.domain {
            if A[i] > A[am] {
                am = i;
            }
        }
        return am;
    }

    // Return a matrix padded by `padding` zeros on each side
    proc pad(const ref x: Tensor(2), padding: int) {
        var t = new Tensor(2,real);
        const (h,w) = x.shape;
        t.reshapeDomain({0..#(h + 2 * padding),0..#(w + 2 * padding)});
        t.data[padding..#h, padding..#w] = x.data;
        return t;
    }

    // Given a volume with shape (m,n,c), return a volume with shape (m + 2 * padding, n + 2 * padding, c)
    proc pad(const ref x: Tensor(3), padding: int) {
        var t = new Tensor(3,real);
        const (h,w,c) = x.shape;
        t.reshapeDomain({0..#(h + 2 * padding),0..#(w + 2 * padding),0..#c});
        forall (i,j,c) in x.data.domain with (ref t) {
            t[i + padding,j + padding,c] = x[i,j,c];
        }
        return t;
    }

    // Compute the resulting tensor shape of a cross correlation
    proc correlateShape(filterShape: 2*int, inputShape: 2*int, stride: int, padding: int) {
        const (kh,kw) = filterShape;
        const (nh,nw) = inputShape;
        if kh != kw then err("Correlation only works with square filters.", kh, " != ", kw);
        return (AutoMath.floor((nh - kh + 2* padding):real / stride:real):int + 1, AutoMath.floor((nw - kw + 2 * padding):real / stride:real):int + 1);
        // return (AutoMath.floor(((nh - kh + padding + stride):real) / (stride:real)):int,AutoMath.floor(((nw - kw + padding + stride):real) / (stride:real)):int);
    }

    // Compute the resulting tensor shape of a cross correlation
    proc correlate(const ref filter: Tensor(?), const ref input: Tensor(?), stride: int = 1, padding: int = 0) {
        if padding > 0 then 
            return correlate_(filter,pad(input,padding),stride,padding);
        return correlate_(filter=filter,input=input,stride,padding);
    }

    // Compute the resulting matrix of a cross correlation
    proc correlate_(const ref filter: Tensor(2), const ref input: Tensor(2), stride: int, padding: int): Tensor(2) {
        const (kh,kw) = filter.shape;
        const (nh,nw) = input.shape;
        if kh != kw then err("Correlation only works with square filters.", kh, " != ", kw);
        // const (outH,outW): 2*int = ((nh - kh + padding + stride) / stride,(nw - kw + padding + stride) / stride);
        const (outH,outW): 2*int = correlateShape((kh,kw),(nh,nw),stride,padding);
        var corr = new Tensor(2,real);
        corr.reshapeDomain({0..#outH,0..#outW});

        forall (x,y) in corr.data.domain with (ref corr) {
            var sum = 0.0;
            forall (i,j) in filter.data.domain with (+ reduce sum) {
                sum += input[x * stride + i, y * stride + j] * filter[i,j];
            }
            corr[x,y] = sum;
        }
        return corr;
    }

    // Compute the sum of cross correlations for each filter and input channel
    proc correlate_(const ref filter: Tensor(3), const ref input: Tensor(3), stride: int, padding: int): Tensor(2) {
        const (kh,kw,cIn) = filter.shape;
        const (nh,nw,nc) = input.shape;
        if kh != kw then err("Correlation only works with square filters.", kh, " != ", kw);
        if cIn != nc then err("Correlation only works with filters and inputs of the same depth.", cIn, " != ", nc);

        // const (outH,outW): 2*int = ((nh - kh + padding + stride) / stride,(nw - kw + padding + stride) / stride);
        const (outH,outW): 2*int = correlateShape((kh,kw),(nh,nw),stride,padding);

        var corr = new Tensor(2,real);
        corr.reshapeDomain({0..#outH,0..#outW});

        forall (x,y) in corr.data.domain with (ref corr) {
            var sum = 0.0;
            forall (i,j,c) in filter.data.domain with (+ reduce sum) {
                sum += input[x * stride + i, y * stride + j,c] * filter[i,j,c];
            }
            corr[x,y] = sum;
        }

        return corr;
    }

    // Compute the resulting tensor shape of a kernel dialation
    proc dialateShape(filterShape: 2*int, stride: int) {
        const (kh,kw) = filterShape;
        return (kh + (stride * (kh - 1)), kw + (stride * (kw - 1)));
    }

    // Dialate a filter
    proc dialate(const ref filter: Tensor(2), stride: int = 1) {
        const (kh,kw) = filter.shape;
        var d = new Tensor(2,real);
        const (dh,dw) = (kh + (stride * (kh - 1)), kw + (stride * (kw - 1)));
        d.reshapeDomain({0..#dh,0..#dw});
        forall (i,j) in filter.data.domain with (ref d) {
            d[i * stride, j * stride] = filter[i,j];
            // d[i + i * stride,j + j * stride] = filter[i,j];
        }
        return d;
    }

    // Dialate a volume of filters
    proc dialate(const ref filter: Tensor(3), stride: int = 1) {
        const (kh,kw,kc) = filter.shape;
        var d = new Tensor(3,real);
        const (dh,dw) = (kh + (stride * (kh - 1)), kw + (stride * (kw - 1)));
        d.reshapeDomain({0..#dh,0..#dw,0..#kc});
        forall (i,j,c) in filter.data.domain with (ref d) {
            d[i * stride,j * stride,c] = filter[i,j,c];

            // d[i + i * stride,j + j * stride,c] = filter[i,j,c];
        }
        return d;
    }

    // Compute the gradient of a loss with respect to a filter
    proc filterGradient(const ref input: Tensor(2), const ref delta: Tensor(2), stride: int = 1, padding: int = 0) {
        const d = dialate(delta,stride - 1);
        return correlate(d,input,stride=1,padding=padding);
    }

    // Compute the gradient of a loss with respect to a volume of filters
    proc filterGradient(const ref input: Tensor(3), const ref delta: Tensor(3), stride: int = 1, padding: int = 0,kernelSize: int) {
        const (inH,inW,inC) = input.shape;
        // writeln("input: ", input.shape);
        // writeln("delta: ", delta.shape);
        const (outH,outW,outC) = delta.shape;

        const (dkh,dkw) = dialateShape((outH,outW),stride - 1);
        // writeln("(dkh,dkw): ", (dkh,dkw));
        const (kh,kw) = correlateShape((dkh,dkw),(inH,inW),stride=1,padding);
        // writeln("(kh,kw): ", (kh,kw));

        var grad = new Tensor(4,real);
        if kh != kernelSize {
            grad.reshapeDomain({0..#outC,0..#kernelSize,0..#kernelSize,0..#inC});
            // writeln("grad: ", grad.shape);
            forall (ci,co) in {0..#inC,0..#outC} with (ref grad, var del = zeros(outH,outW), var img = zeros(inH,inW)) {
                del = delta[..,..,co];
                img = input[..,..,ci];
                const d = dialate(del,stride - 1);
                grad[co,..,..,ci] = correlate(d,img,stride=1,padding=padding)[0..#kernelSize,0..#kernelSize];
            }
            return grad;
        }

        grad.reshapeDomain({0..#outC,0..#kh,0..#kw,0..#inC});
        // writeln("grad: ", grad.shape);
        forall (ci,co) in {0..#inC,0..#outC} with (ref grad, var del = zeros(outH,outW), var img = zeros(inH,inW)) {
            del = delta[..,..,co];
            img = input[..,..,ci];
            const d = dialate(del,stride - 1);
            grad[co,..,..,ci] = correlate(d,img,stride=1,padding=padding);
        }
        return grad;
    }

    // Compute the gradient of a loss with respect to an input
    proc correlateWeight(const ref filter: Tensor(2), pIn: 2*int, pOut: 2*int, stride: int = 1, padding: int = 0) {
        const (m,n) = pIn;
        const (i,j) = pOut;
        const diff = (m - (stride * i - padding), n - (stride * j - padding));
        const (dx,dy) = diff;
        const (kh,kw) = filter.shape;
        if dx >= 0 && dy >= 0 && dx < kh && dy < kw then
            return filter[diff];
        return 0.0;
    }

    // Compute the index of the gradient of a loss with respect to an input. Probably the most important function here.
    proc correlateWeightIdx(filterShape: 2*int, pIn: 2*int, pOut: 2*int, stride: int = 1, padding: int = 0) {
        const (m,n) = pIn;
        const (i,j) = pOut;
        const (dx,dy) = (m - (stride * i - padding), n - (stride * j - padding));
        const (kh,kw) = filterShape;
        if dx >= 0 && dy >= 0 && dx < kh && dy < kw then
            return (dx,dy);
        return (-1,-1);
    }
    
    // Softmax but returns the sum of the exponentials and the exponentials themselves
    proc softmaxParts(t: Tensor(?rank)) {
        const m = max reduce t.data;
        var y = t;
        y.data -= m;
        foreach i in y.data.domain {
            y.data[i] = Math.exp(y.data[i]);
        }
        const sum = + reduce y.data;
        
        return (y,sum,y / sum);
    }

    // Softmax function
    proc softmax(t: Tensor(?rank)) {
        const m = max reduce t.data;
        var y = t;
        y.data -= m;
        foreach i in y.data.domain {
            y.data[i] = Math.exp(y.data[i]);
        }
        const sum = + reduce y.data;
        y.data /= sum;
        return y;
    }

    proc crossEntropyLoss(p: Tensor(1),q: Tensor(1)) {
        var sum = 0.0;
        forall (a,b) in zip(p,q) with (+ reduce sum){
            sum += a * Math.log(b);
        }
        return -sum;
    }

    proc crossEntropyDelta(p: Tensor(1),q: Tensor(1)) {
        return p - q;
    }

    iter convolutionRegions(dom: domain(2,int), k: int, stride: int) {
        const (h,w) = correlateShape((k,k),dom.shape,stride,padding=0);
        for (i,j) in {0..#h,0..#w} {
            yield dom[i * stride..#k,j * stride..#k];
        }
    }

    proc kernelGradient(X: Tensor(2), dY: Tensor(2),kernelSize: int,stride: int = 1) {
        const k = kernelSize;
        const (outH,outW) = correlateShape((k,k),X.shape,stride,padding=0);

        var data: [0..#k,0..#k] real;
        const regions = convolutionRegions(X.domain,k,stride);
        forall (region,i) in zip(regions,0..#dY.domain.size) with (+ reduce data) {
            data += X[region] * dY[indexInShape(dY.shape,i)];
        }
        var dK = new Tensor(2,real);
        dK.reshapeDomain({0..#k,0..#k});
        dK.data = data;
        return dK;
    }






    class IainsRNG {
        var seed: int;
        var state: int;

        proc init(seed: int) {
            this.seed = seed;
            this.state = 0;
            writeln("I was initialized with seed: ", seed);
        }
        proc getNext(): real(64) {
            state += 1;

            const x = (10 * state: real) / 1457.183;
            const y = x + ((10 * state: real + 76.299) / 3947.64);
            const r = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453123;
            return r - AutoMath.floor(r);
        }
    }



















/* these functions were not needed for my final implementation. they are also wrong, but I would like to see the most efficient implementation of them in chapel. */

    proc convolve(kernel: [?dk] ?eltType, X: [?dx] eltType) where dx.rank == 2 && dk.rank == 2 {
        const (h,w) = X.shape;
        const (kh,kw) = kernel.shape;
        const newH = h - (kh - 1);
        const newW = w - (kw - 1);
        var Y: [0..#newH,0..#newW] eltType;
        // forall (i,j) in Y.domain with (var region: [0..#kh,0..#kw] eltType) {
        //     region = X[i..#kh, j..#kw];
        //     Y[i,j] = + reduce (region * kernel);
        // }

        forall (i,j) in Y.domain {
            var sum = 0.0;
            forall (k,l) in kernel.domain with (+ reduce sum) {
                sum += X[i + k, j + l] * kernel[k,l];
            }
            Y[i,j] = sum;
        }
        return Y;
    }


    proc convolveRotateRefPadding(const ref kernel: [?dk] ?eltType, const ref X: [?dx] eltType, ref Y: [?dy] eltType) where dx.rank == 2 && dk.rank == 2 {
        const (h,w) = X.shape;
        const (kh,kw) = kernel.shape;
        const newH = h - (kh - 1);
        const newW = w - (kw - 1);
        // var Y: [0..#newH,0..#newW] eltType;
        
        forall (i,j) in Y.domain {
            var sum = 0.0;
            forall (k,l) in kernel.domain with (+ reduce sum) {
                sum += X[h - i - k - 1, h - j - l - 1] * kernel[k,l];
            }
            Y[i,j] = sum;
        }
        // return Y;
    }

    proc convolveRotate(kernel: [?dk] ?eltType, X: [?dx] eltType) where dx.rank == 2 && dk.rank == 2 {
        const (h,w) = X.shape;
        const (kh,kw) = kernel.shape;
        const newH = h - (kh - 1);
        const newW = w - (kw - 1);
        var Y: [0..#newH,0..#newW] eltType;
        
        forall (i,j) in Y.domain {
            var sum = 0.0;
            forall (k,l) in kernel.domain with (+ reduce sum) {
                sum += X[i + k, j + l] * kernel[kh - k - 1, kw - l - 1];
            }
            Y[i,j] = sum;
        }
        return Y;
    }

    proc convolve(kernel: Tensor(2), X: Tensor(2)): Tensor(2) {
        return new Tensor(convolve(kernel.data,X.data));
    }

    proc rotate180(kernel: [?d] ?eltType) where d.rank == 2 {
        const (kh,kw) = kernel.shape;
        var ker: [0..#kh,0..#kw] eltType;
        forall (i,j) in ker.domain {
            ker[i,j] = kernel[kh - i - 1, kw - j - 1];
        }
        return ker;
    }

    proc rotate180(kernel: Tensor(2)): Tensor(2) {
        return new Tensor(rotate180(kernel.data));
    }

    proc fullConvolve(kernel: [?dk] ?eltType, X: [?dx] eltType) where dx.rank == 2 && dk.rank == 2 {
        const (h,w) = X.shape;
        const (kh,kw) = kernel.shape;
        const (paddingH,paddingW) = (kh - 1,kw - 1);
        const newH = h + 2 * paddingH;
        const newW = w + 2 * paddingW;
        var Y: [0..#newH,0..#newW] eltType;
        Y = 0.0;
        Y[paddingH..#h, paddingW..#w] = X;
        return convolve(kernel,Y);
    }

    proc fullConvolve(kernel: Tensor(2), X: Tensor(2)): Tensor(2) {
        return new Tensor(fullConvolve(kernel.data,X.data));
    }

}

