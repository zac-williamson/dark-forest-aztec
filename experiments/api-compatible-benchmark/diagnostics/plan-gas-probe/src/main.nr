use aztec::macros::aztec;
#[aztec]
pub contract PlanGasProbe {
    use aztec::macros::functions::external;
    #[external("public")]
    fn current_write(count:u32) -> Field {
        let mut plan=libs::state_plan::WritePlan::new();
        for i in 0..count { plan.set(3,i as Field,99,true,[7;32]); }
        plan.words[0]+plan.words[plan.length-1]+plan.length as Field
    }
    #[external("public")]
    fn local_write(count:u32) -> Field {
        let mut words:[Field;384]=[0;384];
        let mut length:u32=0;
        for i in 0..count {
            assert(length+35<=384);
            words[length]=19;
            words[length+1]=i as Field;
            words[length+2]=99;
            for j in 0..32 { words[length+3+j]=7; }
            length+=35;
        }
        words[0]+words[length-1]+length as Field
    }
    #[external("public")]
    fn current_read(count:u32) -> Field {
        let mut plan=libs::state_plan::ReadPlan::new();
        for i in 0..count { plan.add(3,0,i as Field,99,false); }
        plan.words[0]+plan.words[plan.length-1]+plan.length as Field
    }
    #[external("public")]
    fn local_read(count:u32) -> Field {
        let mut words:[Field;320]=[0;320];
        let mut length:u32=0;
        for i in 0..count {
            assert(length+3<=320);
            words[length]=3;
            words[length+1]=i as Field;
            words[length+2]=99;
            length+=3;
        }
        words[0]+words[length-1]+length as Field
    }
}
