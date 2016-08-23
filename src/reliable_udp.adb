--  with Ada.Text_IO;
with Ada.Streams;

package body Reliable_Udp is

   Ack_Mgr      : Ack_Management;

   task body Append_Task is
      Packet_Lost      : Reliable_Udp.Loss;
      Client_Addr      : GNAT.Sockets.Sock_Addr_Type;
      First_D, Last_D  : Interfaces.Unsigned_8;
   begin
      loop
            accept Append (First_Dropped, Last_Dropped   : Interfaces.Unsigned_8;
                           Client_Address                : GNAT.Sockets.Sock_Addr_Type) do
               First_D        := First_Dropped;
               Last_D         := Last_Dropped;
               Client_Addr    := Client_Address;
            end Append;

            for I in Interfaces.Unsigned_8 range First_D .. Last_D loop
               Packet_Lost := (Packet     => I,
                               Last_Ack   => Ada.Real_Time."-"(Ada.Real_Time.Clock,
                               Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max)),
                               From       => Client_Addr);
               Ack_Mgr.Append (Packet_Lost);
            end loop;
      end loop;
   end Append_Task;

   task body Remove_Task is
      Pkt   : Interfaces.Unsigned_8;
   begin
      loop
            accept Remove (Packet : in Interfaces.Unsigned_8) do
               Pkt   := Packet;
            end Remove;
            Ack_Mgr.Add_To_Remove_List (Pkt);
      end loop;
   end Remove_Task;

   task body Rm_Task is
   begin
      accept Start;
      loop
         Ack_Mgr.Remove;
      end loop;
   end Rm_Task;

   task body Ack_Task is
   begin
      Ack_Mgr.Init_Socket;
      accept Start;
      loop
         Ack_Mgr.Ack;
      end loop;
   end Ack_Task;


   protected body Ack_Management is

      procedure Init_Socket is
      begin
         GNAT.Sockets.Create_Socket (Socket,
         GNAT.Sockets.Family_Inet,
         GNAT.Sockets.Socket_Datagram);
      end Init_Socket;


      procedure Append (Packet_Lost : in Loss) is
      begin
         Losses_Container.Append (Container  => Losses,
                                 New_Item    => Packet_Lost);
      end Append;


      procedure Update_AckTime (Position   : in Losses_Container.Cursor;
         Ack_Time    :  in Ada.Real_Time.Time) is
         Element     :  Loss;
      begin
         Element := Losses_Container.Element (Position);
         Element.Last_Ack := Ack_Time;
         Losses_Container.Replace_Element (Losses, Position, Element);
      end Update_AckTime;


      procedure Add_To_Remove_List (Packet : in Interfaces.Unsigned_8) is
      begin
         Rm_Container.Append (Container   => Remove_List,
                              New_Item    => Packet);
      end Add_To_Remove_List;

      procedure Remove is
         Cursor      : Losses_Container.Cursor := Losses.First;
         Rm_Cursor   : Rm_Container.Cursor;
      begin
         while Losses_Container.Has_Element (Cursor) loop

            Rm_Cursor := Remove_List.First;
            while Rm_Container.Has_Element (Rm_Cursor) loop

               if Losses_Container.Element (Cursor).Packet = Rm_Container.Element (Rm_Cursor) then
                  Losses_Container.Delete (Container  => Losses,
                                           Position   => Cursor);
                  Rm_Container.Delete (Container  => Remove_List,
                                       Position   => Rm_Cursor);
               end if;

               Rm_Container.Next (Rm_Cursor);
            end loop;
            Losses_Container.Next (Cursor);
         end loop;
      end Remove;

      function Length return Ada.Containers.Count_Type is
      begin
         return Losses.Length;
      end Length;

      procedure Ack is
         Ack_Array   : array (1 .. 64) of Interfaces.Unsigned_8 := (others => 0);
         Data        : Ada.Streams.Stream_Element_Array (1 .. 64);
         Offset      : Ada.Streams.Stream_Element_Offset;
         Cur_Time    : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
         Cursor      : Losses_Container.Cursor := Losses.First;
         Element     : Loss;

         for Data'Address use Ack_Array'Address;
         use type Ada.Real_Time.Time;
         use type Ada.Real_Time.Time_Span;
      begin
         if Losses_Container.Is_Empty (Losses) = False then
            while Losses_Container.Has_Element (Cursor) loop
               Element := Losses_Container.Element (Cursor);
               if Cur_Time - Element.Last_Ack >
                  Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max)
               then
                  Element.Last_Ack := Ada.Real_Time.Clock;
                  Losses_Container.Replace_Element (Losses, Cursor, Element);
                  Ack_Array (1) := Element.Packet;
                  GNAT.Sockets.Send_Socket (Socket, Data, Offset, Element.From);
                  Update_AckTime (Cursor, Ada.Real_Time.Clock);
               end if;
               Losses_Container.Next (Cursor);
            end loop;
         end if;
      end Ack;

   end Ack_Management;

end Reliable_Udp;
