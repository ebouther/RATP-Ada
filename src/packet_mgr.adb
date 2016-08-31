with Ada.Text_IO;

package body Packet_Mgr is

   Buffer_Mgr              : Buffer_Management;
   --  Log_Seq_Nb              : Natural := 1;

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

  --   task body Container_To_CSV is
  --      Pkt_Content : Packet_Content;
  --      Filled_Buf  : Container;
  --      Log_File    : Ada.Text_IO.File_Type;
  --      Packet_U64  : Interfaces.Unsigned_64;
  --      for Packet_U64'Address use Pkt_Content (2)'Address;
  --   begin
  --      loop
  --         accept Log (Buffer   : Container) do
  --            Filled_Buf := Buffer;
  --         end Log;
  --         Ada.Text_IO.Open (Log_File, Ada.Text_IO.Append_File, "recv.csv");
  --         Ada.Text_IO.Put_Line (Log_File, "---------------- Full Buffer [" &
  --            Log_Seq_Nb'Img & "] State -----------------");
  --         for I in Natural range 1 .. Base_Udp.Sequence_Size loop
  --            Pkt_Content := Filled_Buf.Buffer (I);
  --            Ada.Text_IO.Put_Line (Log_File, I'Img & Packet_U64'Img);
  --         end loop;
  --         Ada.Text_IO.Put_Line (Log_File, "----------------------------------------------------");
  --         Ada.Text_IO.Close (Log_File);
  --         Log_Seq_Nb := Log_Seq_Nb + 1;
  --      end loop;
  --   end Container_To_CSV;

   package Packet_Buffers is new
      Buffers.Generic_Buffers (Element_Type => Packet_Payload);

  --   procedure Producer (Buffer : Buffers.Local.Local_Buffer_Access) is
  --      begin
  --         declare
  --            use Unsigned_32_Buffers;
  --            Buffer_Handle : Buffers.Buffer_Handle_Type;
  --         begin
  --            Buffer.Get_Free_Buffer (Buffer_Handle);
  --            declare
  --               type Data_Array is new
  --                 Element_Array
  --                 (1 .. To_Word_Count
  --                  (Buffers.Get_Available_Bytes (Buffer_Handle)));
  --               Datas : Data_Array;
  --               for Datas'Address use Buffers.Get_Address (Buffer_Handle);
  --            begin
  --               for I in Datas'Range loop
  --                  Datas (I) := Interfaces.Unsigned_32 (I);
  --               end loop;
  --               Buffers.Set_Used_Bytes (Buffer_Handle,
  --                                       To_Bytes (Datas'Length));
  --            end;
  --            Buffer.Release_Free_Buffer (Buffer_Handle);
  --                  end;
  --   end Producer;

   task body Consumer_Task is
   begin
      loop
         declare
            use Packet_Buffers;
            Buffer_Handle : Buffers.Buffer_Handle_Type;
         begin
            Buffer.Get_Full_Buffer (Buffer_Handle);
            declare

               type Data_Array is new Element_Array
                 (1 .. To_Word_Count
                  (Buffers.Get_Used_Bytes (Buffer_Handle)));

               Datas : Data_Array;

               for Datas'Address use Buffers.Get_Address (Buffer_Handle);
            begin
               Ada.Text_IO.Put_Line ("Released");
               --  Ada.Text_IO.Put_Line ("data (data'first) : " &
               --                        Datas (Datas'First)'Img);
            end;
            Buffer.Release_Full_Buffer (Buffer_Handle);
         exception
            when E : others =>
               Ada.Text_IO.Put_Line ("exception : " &
                                     Ada.Exceptions.Exception_Name (E) &
                                     " message : " &
                                     Ada.Exceptions.Exception_Message (E));
         end;
      end loop;
   end Consumer_Task;

   task body Store_Packet_Task is
      Pkt_Content    : Packet_Payload;
      Pkt_Nb         : Base_Udp.Header;
      New_Seq, Ack   : Boolean;

      Buffer_Handle  : Buffers.Buffer_Handle_Type;
      Buffer         : aliased Buffers.Local.Local_Buffer_Access;
      type Data_Array is new
        Packet_Buffers.Element_Array
        (1 .. Packet_Buffers.To_Word_Count
         (Buffers.Get_Available_Bytes (Buffer_Handle)));
      Datas : Data_Array;
      for Datas'Address use Buffers.Get_Address (Buffer_Handle);
      for Pkt_Nb'Address use Pkt_Content'Address;
   begin
      Buffer.Initialise (100, Size => (Packet_Payload'Size / System.Storage_Unit) * Base_Udp.Pkt_Max);
      Buffer.Get_Free_Buffer (Buffer_Handle);
      loop
         select
            accept Store (Data            : Packet_Payload;
                          New_Sequence    : Boolean;
                          Is_Ack          : Boolean) do
               Pkt_Content := Data;
               New_Seq     := New_Sequence;
               Ack         := Is_Ack;
            end Store;

            if New_Seq then
               Buffer.Release_Free_Buffer (Buffer_Handle);
               Buffer.Get_Free_Buffer (Buffer_Handle);
            end if;

            declare
               Datas : Data_Array;
               Pkt   : Packet_Payload := (others => 0);
               for Datas'Address use Buffers.Get_Address (Buffer_Handle);
            begin
               Datas (Pkt_Nb + 1) := Pkt_Content;
               Buffers.Set_Used_Bytes (Buffer_Handle,
                                       To_Bytes (Datas'Length));
            end;
         else
            Ada.Text_IO.Put_Line ("Store Packet Task Busy...");
         end select;
      end loop;
      exception
            when E : others =>
               Ada.Text_IO.Put_Line ("exception : " &
                                     Ada.Exceptions.Exception_Name (E) &
                                     " message : " &
                                     Ada.Exceptions.Exception_Message (E));
   end Store_Packet_Task;


   protected body Buffer_Management is

      procedure Store_Packet (Data           : Packet_Content;
                              New_Sequence   : Boolean;
                              Is_Ack         : Boolean) is
         Seq_Nb         : Base_Udp.Header;
         Content        : Packet_Content;
         Cur_Container  : Container_Ptr := Pkt_Containers.Near_Full;
         Tmp            : array (1 .. 2) of Container_Ptr;
         for Content'Address use Data'Address;
         for Seq_Nb'Address use Data'Address;
      begin
         if New_Sequence then
            --  Cur_Container := Pkt_Containers.Swap;
            pragma Warnings (Off);
            pragma Warnings (On);
         end if;

         if Pkt_Containers.Near_Full.Free_Space = 0 then

            Tmp (1) := Pkt_Containers.Swap;
            Tmp (2) := Pkt_Containers.Full;
            Pkt_Containers.Full := Pkt_Containers.Near_Full;
            Pkt_Containers.Near_Full := Tmp (1);
            Pkt_Containers.Swap := Tmp (2);

            ------- DBG -----------
            pragma Warnings (Off);
            --  Container_To_CSV_Task.Log (Pkt_Containers.Full.all);
            pragma Warnings (On);
            ------------------------

            Pkt_Containers.Full.Buffer := (others => (others => 0));
            Pkt_Containers.Full.Free_Space := Base_Udp.Header (Base_Udp.Sequence_Size);
         end if;

         if Is_Ack then
            pragma Warnings (Off);
            pragma Warnings (On);
         end if;
         if Pkt_Containers.Near_Full.Buffer (Interfaces.Unsigned_64 (Seq_Nb) + 1) (42) = 0 then
            Cur_Container := Pkt_Containers.Near_Full;
         else
            Cur_Container := Pkt_Containers.Swap;
            if Pkt_Containers.Swap.Buffer (Interfaces.Unsigned_64 (Seq_Nb) + 1) (42) = 0 then
               Ada.Text_IO.Put_Line ("***********|| ERROR ||***********" &
                  "Not enough buffer (Swap already used)");
            end if;
         end if;
         --  end if;

         ------- DBG ------
         Cur_Container.Buffer (Interfaces.Unsigned_64 (Seq_Nb) + 1) (42) := 1;
         ------------------
         Cur_Container.Buffer (Interfaces.Unsigned_64 (Seq_Nb) + 1) := Content;
         Cur_Container.Free_Space := Cur_Container.Free_Space - 1;

      end Store_Packet;

   end Buffer_Management;

end Packet_Mgr;
