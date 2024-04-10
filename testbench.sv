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

