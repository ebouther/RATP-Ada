with System;

with Base_Udp;
with Buffers.Local;

package Packet_Mgr is

   --  Number of pmh buffers initialized
   PMH_Buf_Nb     : constant := 8;

   type Handle_Index is mod PMH_Buf_Nb;

   type State_Enum is (Empty, Near_Full, Full);

   type Handler is limited
      record
         Handle    : Buffers.Buffer_Handle_Type;
         State     : State_Enum := Empty;
      end record;

   --  Do not forget to check if current = first after a complete cycle
   --  as Index_Handle is used in a circular way. Must not happen.
   type Handle_Array is array (Handle_Index'First .. Handle_Index'Last) of Handler;

   package Packet_Buffers is new
      Buffers.Generic_Buffers
         (Element_Type => Base_Udp.Packet_Stream);

   type Buf_Handler is
      record
         Buffer      : aliased Buffers.Local.Local_Buffer_Type;
         Handlers    : Handle_Array;
         First       : Handle_Index;
         Current     : Handle_Index;
      end record;

   procedure Init_Handle_Array;
   procedure Release_Free_Buffer_At (Index : in Handle_Index);
   procedure Get_Filled_Buf (To_File   : in Boolean := True);
   procedure Save_Ack (Seq_Nb          :  in Base_Udp.Header;
                       Packet_Number   :  in Base_Udp.Header;
                       Data            :  in Base_Udp.Packet_Stream);

   task type Release_Full_Buf is
      entry Start;
   end Release_Full_Buf;

   task type PMH_Buffer_Addr is
      entry Stop;
      entry New_Buffer_Addr (Buffer_Ptr : in out System.Address);
   end PMH_Buffer_Addr;

end Packet_Mgr;
