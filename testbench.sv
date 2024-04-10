class transaction;
  rand bit rd, wr;
  rand bit [7:0] data_in;
  bit empty, full;
  bit [7:0] data_out;
  
  constraint rd_wr {
    rd != wr;
    wr dist { 0:/50, 1:/50};
    rd dist { 0:/50, 1:/50};
  }
  
  constraint data_con {
    data_in > 1;
    data_in < 5;
  }
  
  function void display(input string tag);
     $display("[%0s] : WR : %0b\t RD:%0b\t DATAWR : %0d\t DATARD : %0d\t FULL : %0b\t EMPTY : %0b @ %0t", tag, wr, rd, data_in, data_out, full, empty,$time);   
  endfunction
  
  function transaction copy();
    copy = new();
    copy.rd = this.rd;
    copy.wr = this.wr;
    copy.data_in = this.data_in;
    copy.data_out = this.data_out;
    copy.full = this.full;
    copy.empty = this.empty;
  endfunction
endclass


class generator;
  //randomize transaction
  //send transaction to the driver
  //sense transaction from SCO and driver -> next transaction
  
  transaction tr;
  mailbox #(transaction) mbx;  //data will be transferring from gen to drv through mailbox
  int count = 0;
  event next;   //when to send next transac
  event done;   //conveys no of requested transac completed
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    tr = new();
  endfunction
  
  
  task run();
    repeat (count)
      begin
        assert (tr.randomize()) else $error("Randomization Failed");
        mbx.put(tr.copy); //As randmization is success we want to send the transaction copy                             to the driver class
        tr.display("GEN");
        @(next); //waiting to receive the trigger from another class to send the                             transaction
      end
    
    ->done; // will be triggered when the no of counts transaction will be completed
  
  endtask
endclass

class driver;
  //receive transac from gen
  //Apply reset to dut
  //Apply transac to dut with interface
  //Notify Gen - > completeion of interface trigger
  
  virtual fifo_if vif;
  
  mailbox #(transaction) mbx;
  
  transaction datac;
  event next;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    
  endfunction
  
  
  task reset();
    vif.rst <= 1'b1;
    vif.rd <= 0;
    vif.wr <= 0;
    vif.data_in <= 0;
    repeat (5) @(posedge vif.clock);
    vif.rst <= 1'b0;
  endtask
  
  task run();    //Applying Random Stimulus to DUT
    forever 
      begin
        mbx.get(datac);
        datac.display("DRV");
        vif.rd <= datac.rd;
        vif.wr <= datac.wr;
        vif.data_in <= datac.data_in;
        repeat (2) @(posedge vif.clock);
        
      end
  endtask
endclass

class monitor;
  //capture DUT response
  //send response transaction to scoreboard
  //control data to be send for specific operation
  
  virtual fifo_if vif;
  transaction tr;
  mailbox #(transaction) mbx;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    //count = 0;
  endfunction
  
  task run();
    tr = new();
    forever
      begin
        repeat (2) @(posedge vif.clock);
        tr.rd <= vif.rd;
        tr.wr <= vif.wr;
        tr.data_in <= vif.data_in;
        tr.full <= vif.full;
        tr.empty <= vif.empty;
        tr.data_out <= vif.data_out;
        mbx.put(tr);
        tr.display("Mon");
          
      end
  endtask
endclass


class scoreboard;
  
  //receive transac from monitor
  //store transac
  //compare with expected result
  mailbox #(transaction) mbx;
  transaction tr;
  event next;
  
  bit [7:0] din [$]; ////Queue will help to push/write data in queue and read/pop data
                     //will help in not to worry about arrangement of data
  bit [7:0] temp;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    
  endfunction
  
  task run();
    forever
      begin
        mbx.get(tr);
        tr.display("SCO");
        if (tr.wr == 1'b1)
          begin
            din.push_front(tr.data_in);
            $display(" [SCO] Data stored in queue : %0d", tr.data_in);
          end
        
        if (tr.rd == 1'b1)
          begin
            if (tr.empty == 1'b0)
              begin
                temp = din.pop_back();
                if (tr.data_out == temp)
                  $display(" [SCO] Data Matched");
                else
                  $display("Data Mismatched");
              end
            else
              $display("fifo is empty");
          end
        
        ->next;
      end
  endtask
  
  
endclass


class environment;
  //holds all classes together
  //schedule different processes
  //connects mailbox events
  
  generator gen;
  driver drv;
  mailbox #(transaction) gdmbx;
  
  
  monitor mon;
  scoreboard sco;
  mailbox #(transaction) msmbx;
  
  event nextgs;
  
  virtual fifo_if vif;
  
  function new(virtual fifo_if vif);
    gdmbx = new();
    gen = new(gdmbx);
    drv = new(gdmbx);
    
    msmbx = new();
    mon = new(msmbx);
    sco = new(msmbx);
    
    this.vif = vif;
    
    drv.vif = this.vif;
    mon.vif = this.vif;
    
    gen.next = nextgs;
    sco.next = nextgs;
  endfunction
  
  task pre_test();
    drv.reset();
  endtask
  
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
    
  endtask
  
  task post_test();
    wait(gen.done.triggered);
    $finish;
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
  
endclass


module tb;
    
   
    
    fifo_if vif();
  fifo dut (vif.clock, vif.rd, vif.wr,vif.full, vif.empty, vif.data_in, vif.data_out, vif.rst);
    
    initial begin
      vif.clock <= 0;
    end
    
    always #10 vif.clock <= ~vif.clock;
    
    environment env;
    
    
    
    initial begin
      env = new(vif);
      env.gen.count = 20;
      env.run();
    end
      
    
    initial begin
      $dumpfile("dump.vcd");
      $dumpvars;
    end
   
    
endmodule

