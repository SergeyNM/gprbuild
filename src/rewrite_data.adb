------------------------------------------------------------------------------
--                         GNAT COMPILER COMPONENTS                         --
--                                                                          --
--                         R E W R I T E _ D A T A                          --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--            Copyright (C) 2012, Free Software Foundation, Inc.            --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with Ada.Unchecked_Conversion;

package body Rewrite_Data is

   use Ada;

   subtype SEO is Stream_Element_Offset;

   ------------
   -- Create --
   ------------

   function Create
     (Pattern, Value : String;
      Size           : Stream_Element_Offset := 1_024) return Buffer
   is

      subtype SP   is String (1 .. Pattern'Length);
      subtype SEAP is Stream_Element_Array (1 .. Pattern'Length);

      subtype SV   is String (1 .. Value'Length);
      subtype SEAV is Stream_Element_Array (1 .. Value'Length);

      function To_SEAP is new Unchecked_Conversion (SP, SEAP);
      function To_SEAV is new Unchecked_Conversion (SV, SEAV);

   begin
      return B : Buffer
        (SEO'Max (Size, SEO (Pattern'Length)), -- can't be smaller than pattern
         SEO (Pattern'Length),
         SEO (Value'Length))
      do
         B.Pattern := To_SEAP (Pattern);
         B.Value   := To_SEAV (Value);
         B.Pos_C   := 0;
         B.Pos_B   := 0;
      end return;
   end Create;

   -----------
   -- Flush --
   -----------

   procedure Flush
     (B      : in out Buffer;
      Output : not null access procedure (Data : Stream_Element_Array)) is
   begin
      if B.Pos_B > 0 then
         Output (B.Buffer (1 .. B.Pos_B));
      end if;

      if B.Pos_C > 0 then
         Output (B.Current (1 .. B.Pos_C));
      end if;

      Reset (B);
   end Flush;

   -----------
   -- Reset --
   -----------

   procedure Reset (B : in out Buffer) is
   begin
      B.Pos_B := 0;
      B.Pos_C := 0;
   end Reset;

   -------------
   -- Rewrite --
   -------------

   procedure Rewrite
     (B      : in out Buffer;
      Input  : not null access procedure
                 (Buffer : out Stream_Element_Array;
                  Last   : out Stream_Element_Offset);
      Output : not null access procedure (Data : Stream_Element_Array))
   is
      Buffer : Stream_Element_Array (1 .. B.Size);
      Last   : Stream_Element_Offset;
   begin
      Rewrite_All : loop
         Input (Buffer, Last);
         exit Rewrite_All when Last = 0;
         Write (B, Buffer (1 .. Last), Output);
      end loop Rewrite_All;

      Flush (B, Output);
   end Rewrite;

   ----------
   -- Size --
   ----------

   function Size (B : Buffer) return Natural is
   begin
      return Natural (B.Pos_B + B.Pos_C);
   end Size;

   -----------
   -- Write --
   -----------

   procedure Write
     (B      : in out Buffer;
      Data   : Stream_Element_Array;
      Output : not null access procedure (Data : Stream_Element_Array))
   is

      procedure Need_Space (Size : Stream_Element_Offset);
      pragma Inline (Need_Space);

      ----------------
      -- Need_Space --
      ----------------

      procedure Need_Space (Size : Stream_Element_Offset) is
      begin
         if B.Pos_B + Size > B.Size then
            Output (B.Buffer (1 .. B.Pos_B));
            B.Pos_B := 0;
         end if;
      end Need_Space;

   begin
      if B.Size_Pattern = 0 then
         Output (Data);

      else
         for K in Data'Range loop
            if Data (K) = B.Pattern (B.Pos_C + 1) then
               --  Store possible start of a macth
               B.Pos_C := B.Pos_C + 1;
               B.Current (B.Pos_C) := Data (K);

            else
               --  Not part of pattern, if a start of a match was found,
               --  remove it.

               if B.Pos_C /= 0 then
                  Need_Space (B.Pos_C);

                  B.Buffer (B.Pos_B + 1 .. B.Pos_B + B.Pos_C) :=
                    B.Current (1 .. B.Pos_C);
                  B.Pos_B := B.Pos_B + B.Pos_C;
                  B.Pos_C := 0;
               end if;

               Need_Space (1);
               B.Pos_B := B.Pos_B + 1;
               B.Buffer (B.Pos_B) := Data (K);
            end if;

            if B.Pos_C = B.Size_Pattern then
               --  The pattern is found

               Need_Space (B.Size_Value);

               B.Buffer (B.Pos_B + 1 .. B.Pos_B + B.Size_Value) := B.Value;
               B.Pos_C := 0;
               B.Pos_B := B.Pos_B + B.Size_Value;
            end if;
         end loop;
      end if;
   end Write;

end Rewrite_Data;
