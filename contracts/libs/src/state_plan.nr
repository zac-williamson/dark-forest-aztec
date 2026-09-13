// Public settlement plans. Original typed arguments remain the source of every payload.
// Descriptors are bounded metadata; game Field/u128 values are never packed or narrowed.
pub struct ReadPlan { pub words: [Field; 320], pub length: u32 }
impl ReadPlan {
    #[inline_never]
    pub unconstrained fn new() -> Self { Self { words: [0; 320], length: 0 } }
    #[inline_never]
    pub unconstrained fn add(&mut self, namespace: u8, group: u8, key: Field, expected: Field, initialized: bool) {
        assert(self.length + 3 <= 320, "Read plan capacity exceeded");
        let descriptor = namespace as u32 + (group as u32) * 16 + if initialized { 256 } else { 0 };
        self.words[self.length] = descriptor as Field;
        self.words[self.length + 1] = key;
        self.words[self.length + 2] = expected;
        self.length += 3;
    }
    #[inline_never]
    pub unconstrained fn batch(&mut self, namespace: u8, group: u8, ids: [Field; 20], hashes: [Field; 20], count: u32) {
        // Invalid bounds are rejected at the original assertion position in the System.
        let count = if count <= 20 { count } else { 20 };
        for i in 0..count { if ids[i] != 0 { self.add(namespace, group, ids[i], hashes[i], false); } }
    }
    #[inline_never]
    pub unconstrained fn small(self) -> [Field; 32] {
        assert(self.length <= 32, "Read plan is not small");
        let mut result = [0; 32];
        for i in 0..self.length { result[i] = self.words[i]; }
        result
    }
}
pub struct WritePlan { pub words: [Field; 384], pub length: u32 }
impl WritePlan {
    #[inline_never]
    pub unconstrained fn new() -> Self { Self { words: [0; 384], length: 0 } }
    #[inline_never]
    pub unconstrained fn append<let N: u32>(&mut self, fields: [Field; N]) {
        assert(self.length + N <= 384, "Write plan capacity exceeded");
        for i in 0..N { self.words[self.length + i] = fields[i]; }
        self.length += N;
    }
    #[inline_never]
    pub unconstrained fn set<let N: u32>(&mut self, namespace: u8, key: Field, root: Field, prepared: bool, state: [Field; N]) {
        let descriptor = namespace as u32 + if prepared { 16 } else { 0 };
        self.append([descriptor as Field, key, root]);
        self.append(state);
    }
    #[inline_never]
    pub unconstrained fn authorize_batch(&mut self, namespace: u8, count: u32, maximum: u32) {
        // This record retains authorization-before-bound-check even for count zero.
        self.append([(namespace as u32 + 32) as Field, count as Field, maximum as Field]);
    }
    #[inline_never]
    pub unconstrained fn start_batch(&mut self, namespace: u8, count: u32, maximum: u32) -> u32 {
        let start=self.length;
        if count == 0 {
            self.authorize_batch(namespace,count,maximum);
        } else {
            // Explicit batch boundary and original bound precede compact live items.
            self.append([(namespace as u32 + 64) as Field,count as Field,maximum as Field,0]);
        }
        start
    }
    #[inline_never]
    pub unconstrained fn append_batch_item<let N: u32>(&mut self, start:u32, key:Field, state:[Field;N]) {
        self.append([key]);
        self.append(state);
        self.words[start+3]+=1;
    }
    #[inline_never]
    pub unconstrained fn small(self) -> [Field; 128] {
        assert(self.length <= 128, "Write plan is not small");
        let mut result = [0; 128];
        for i in 0..self.length { result[i] = self.words[i]; }
        result
    }
}
#[inline_never]
pub unconstrained fn take<let N: u32>(words: [Field;384], offset: u32) -> [Field; N] {
    assert(offset + N <= words.len(), "Truncated plan payload");
    let mut fields = [0; N];
    for i in 0..N { fields[i] = words[offset + i]; }
    fields
}
#[inline_never]
pub unconstrained fn safe_has_nonzero_ids(ids: [Field; 20], count: u32) -> bool {
    let count = if count <= 20 { count } else { 20 };
    let mut any = false;
    for i in 0..count { if ids[i] != 0 { any = true; } }
    any
}

#[test]
unconstrained fn read_plan_keeps_scalar_zero_and_skips_only_inactive_batch_ids() {
    let mut plan = ReadPlan::new();
    plan.add(8, 0, 0, 99, false);
    let mut ids = [0;20]; ids[0] = 42; ids[19] = 123;
    let mut hashes = [0;20]; hashes[0] = 51; hashes[19] = 456;
    plan.batch(8,1,ids,hashes,2);
    assert(plan.length == 6);
    assert(plan.words[1] == 0);
    assert(plan.words[2] == 99);
    assert(plan.words[4] == 42);
    assert(plan.words[5] == 51);
    assert(plan.small()[5] == 51);
}

#[test]
unconstrained fn read_plan_covers_full_find_read_set() {
    let mut plan = ReadPlan::new();
    for i in 0..5 { plan.add(3,i as u8,i as Field,0,false); }
    let ids = [1;20];
    let hashes = [2;20];
    for i in 0..5 { plan.batch(8,(i+5) as u8,ids,hashes,20); }
    assert(plan.length == 315);
    assert(plan.words[314] == 2);
}

#[test]
unconstrained fn write_plan_keeps_zero_payload_and_auth_only_empty_batch() {
    let mut plan = WritePlan::new();
    plan.set(9,0,7,true,[0;3]);
    plan.authorize_batch(9,0,20);
    assert(plan.length == 9);
    assert(plan.words[0] == 25);
    assert(plan.words[1] == 0);
    assert(plan.words[2] == 7);
    assert(plan.words[6] == 41);
    assert(plan.words[7] == 0);
    assert(plan.words[8] == 20);
}

#[test]
unconstrained fn write_plan_covers_full_spaceships_and_arrival_locations() {
    let mut plan = WritePlan::new();
    plan.set(3,1,0,true,[0;32]);
    plan.set(5,1,0,true,[0;22]);
    plan.set(6,1,0,true,[0;22]);
    plan.authorize_batch(9,20,20);
    for i in 0..20 { plan.set(9,i as Field,0,false,[0;3]); }
    plan.set(2,1,0,true,[0;8]);
    plan.authorize_batch(8,5,5);
    for i in 0..5 { plan.set(8,i as Field,0,false,[0;13]); }
    plan.authorize_batch(9,5,5);
    for i in 0..5 { plan.set(9,i as Field,0,false,[0;3]); }
    assert(plan.length == 335);
}

#[test]
unconstrained fn write_plan_literal_transport_preserves_zero_inactive_words() {
    let mut plan=WritePlan::new();
    for i in 0..384 { assert(plan.words[i]==0); }
    plan.set(3,-1,-2,true,[3;32]);
    plan.authorize_batch(9,0,20);
    for i in 0..384 { if i>=plan.length { assert(plan.words[i]==0); } }
    plan.set(6,-3,-4,true,[-1;22]);
    plan.set(5,-5,-6,true,[-2;22]);
    plan.authorize_batch(9,20,20);
    for i in 0..20 { plan.set(9,i as Field,-7,false,[-3;3]); }
    plan.authorize_batch(8,5,5);
    for i in 0..5 { plan.set(8,i as Field,-8,false,[-4;13]); }
    plan.authorize_batch(9,5,5);
    for i in 0..5 { plan.set(9,i as Field,-9,false,[-5;3]); }
    assert(plan.length==327);
    for i in 0..384 { if i>=plan.length { assert(plan.words[i]==0); } }
}

#[test]
unconstrained fn write_plan_compact_batches_preserve_order_duplicates_and_full_fields() {
    let mut plan=WritePlan::new();
    let first=plan.start_batch(9,4,20);
    plan.append_batch_item(first,-1,[-1,0,0x100000000000000000000000000000000000000000000000000]);
    plan.append_batch_item(first,-1,[7,8,9]);
    // Zero IDs were skipped by the original batch; duplicate nonzero IDs remain.
    plan.set(3,77,88,true,[19;32]);
    let second=plan.start_batch(9,1,20);
    plan.append_batch_item(second,3,[21,22,23]);
    assert_eq(first,0);
    assert_eq(second,47);
    assert_eq(plan.length,55);
    assert_eq([plan.words[0],plan.words[1],plan.words[2],plan.words[3]],[73,4,20,2]);
    assert_eq([plan.words[4],plan.words[5],plan.words[6],plan.words[7]],[-1,-1,0,0x100000000000000000000000000000000000000000000000000]);
    assert_eq([plan.words[8],plan.words[9],plan.words[10],plan.words[11]],[-1,7,8,9]);
    assert_eq([plan.words[12],plan.words[13],plan.words[14]],[19,77,88]);
    assert_eq([plan.words[47],plan.words[48],plan.words[49],plan.words[50]],[73,1,20,1]);
    assert_eq([plan.words[51],plan.words[52],plan.words[53],plan.words[54]],[3,21,22,23]);
    for i in 55..384 { assert_eq(plan.words[i],0); }
}

#[test]
unconstrained fn write_plan_compact_batches_preserve_empty_auth_and_maximum_capacity() {
    let mut plan=WritePlan::new();
    let _empty=plan.start_batch(9,0,20);
    assert_eq(plan.length,3);
    assert_eq([plan.words[0],plan.words[1],plan.words[2]],[41,0,20]);
    let first=plan.start_batch(9,20,20);
    for i in 0..20 { plan.append_batch_item(first,(i+1) as Field,[-1,-2,-3]); }
    let ships=plan.start_batch(8,5,5);
    for i in 0..5 { plan.append_batch_item(ships,(i+100) as Field,[-4;13]); }
    let locations=plan.start_batch(9,5,5);
    for i in 0..5 { plan.append_batch_item(locations,(i+100) as Field,[-5;3]); }
    assert_eq(plan.length,185);
    assert_eq(plan.words[first+3],20);
    assert_eq(plan.words[ships+3],5);
    assert_eq(plan.words[locations+3],5);
    assert_eq([plan.words[first+4],plan.words[first+80]],[1,20]);
    assert_eq([plan.words[ships+4],plan.words[ships+60]],[100,104]);
    assert_eq([plan.words[locations+4],plan.words[locations+20]],[100,104]);
    for i in 185..384 { assert_eq(plan.words[i],0); }
}
