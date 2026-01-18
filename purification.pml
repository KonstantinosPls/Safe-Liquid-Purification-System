/*CCS2420 Formal Methods & SW Reliability
    Safe Liquid Purification System   */

/* created message types for clarity and easier debugging */
mtype = {
    /* message types for the blue channel which has bidirectional communication */
    status_query, status_query_ack,
    req_filling, req_filling_ack,
    filling, filling_ack,

    /* message types for the red channel which is unidirectional and used for vessel state updates (OutCtrl -> InCtrl) */
    empty_state, ready_state, filled_state,

    /* valve commands */
    open_cmd, close_cmd
};

/* Assignment's unsafe system */
#define liquid 1

chan Vessel = [2] of { bit };

/* Macro for safety property (nfull cannot be used directly in LTL) */
#define vesselNotFull (len(Vessel) < 2)

/* Communication Channels */

/* We split the bidirectional blue channel into two unidirectional ones for ease of use */
chan blue_in2out = [1] of { mtype };
chan blue_out2in = [1] of { mtype };

chan red = [1] of { mtype }; 

/* Controller for the valve command channels */
chan inValveCmd = [1] of { mtype };
chan outValveCmd = [1] of { mtype };


/* Valve states */
bool inValveOpen = false;
bool outValveOpen = false;

/* Vessel state tracking (for LTL properties) */
mtype vesselState = empty_state;

/* Modified Valve Processes */

proctype InValve(chan outflow) {
    do
    :: inValveCmd?open_cmd ->
        inValveOpen = true;
        outflow!liquid           
    :: inValveCmd?close_cmd ->
        inValveOpen = false
    od
}

proctype OutValve(chan inflow) {
    do
    :: outValveCmd?open_cmd ->
        outValveOpen = true;
        inflow?liquid  /* receive liquid from vesel */
    :: outValveCmd?close_cmd ->
        outValveOpen = false
    od
}

/* Controller Processes */

proctype InValveCtrl() {
    mtype currentState;

    do
    ::  
        blue_in2out!status_query
        blue_out2in?status_query_ack
        red?currentState
        if
        :: currentState == empty_state ->
                blue_in2out!req_filling
                blue_out2in?req_filling_ack
                red?currentState 

                inValveCmd!open_cmd
                blue_in2out!filling
                blue_out2in?filling_ack
                red?currentState
                inValveCmd!close_cmd

                /* Wait for vessel to be emptied before next cycle */
                red?currentState
        ::  else -> skip
        fi

    od
}

proctype OutValveCtrl() {
    do
    :: blue_in2out?status_query ->
        /* Respond to status query */
        blue_out2in!status_query_ack;
        red!vesselState

    :: blue_in2out?req_filling ->
        /* Handle filling request: close out-valve, set ready */
        blue_out2in!req_filling_ack;
        outValveCmd!close_cmd;
        vesselState = ready_state;
        red!ready_state

    :: blue_in2out?filling ->
        /* Handle filling notification: update state to filled */
        blue_out2in!filling_ack;
        vesselState = filled_state;
        red!filled_state;

        /* Simulate processing complete: empty the vessel */
        outValveCmd!open_cmd;
        vesselState = empty_state;
        red!empty_state
    od
}

init {
    atomic {
        run InValve(Vessel);
        run OutValve(Vessel);
        run InValveCtrl();
        run OutValveCtrl();
    }
}

/* LTL Properties */

/* Safety property: The vessel never becomes full */
ltl safety { [] vesselNotFull }

/* Liveness property: The system keeps operating and it is always eventually empty AND filled */
ltl liveness { ([] <> (vesselState == empty_state)) && ([] <> (vesselState == filled_state)) }
