------------------------------------------------------------------------------
--                                                                          --
--                         GNAT COMPILER COMPONENTS                         --
--                                                                          --
--                            G P R _ U T I L                               --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--            Copyright (C) 2007-2009, Free Software Foundation, Inc.       --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 2,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT;  see file COPYING.  If not, write --
-- to  the  Free Software Foundation,  51  Franklin  Street,  Fifth  Floor, --
-- Boston, MA 02110-1301, USA.                                              --
--                                                                          --
-- GNAT was originally developed  by the GNAT team at  New York University. --
-- Extensive contributions were provided by Ada Core Technologies Inc.      --
--                                                                          --
------------------------------------------------------------------------------

with Debug;    use Debug;
with Err_Vars; use Err_Vars;
with Errutil;
with Makeutl;  use Makeutl;
with Opt;      use Opt;
with Osint;    use Osint;
with Output;   use Output;
with Snames;   use Snames;
with Tempdir;
with Types;    use Types;
with GprConfig.Sdefault;        use GprConfig.Sdefault;
with GNAT.Directory_Operations; use GNAT.Directory_Operations;

package body Gpr_Util is

   GNU_Header  : aliased constant String := "INPUT (";
   GNU_Opening : aliased constant String := """";
   GNU_Closing : aliased constant String := '"' & ASCII.LF;
   GNU_Footer  : aliased constant String := ')' & ASCII.LF;

   -------------------------------
   -- Binder_Exchange_File_Name --
   -------------------------------

   function Binder_Exchange_File_Name
     (Main_Base_Name : File_Name_Type; Prefix : Name_Id)
      return String_Access
   is
      File_Name : constant String := Get_Name_String (Main_Base_Name);
   begin
      Get_Name_String (Prefix);
      Add_Str_To_Name_Buffer (File_Name);
      Add_Str_To_Name_Buffer (Binder_Exchange_Suffix);
      return new String'(Name_Buffer (1 .. Name_Len));
   end Binder_Exchange_File_Name;

   --------------------------
   -- Create_Response_File --
   --------------------------

   procedure Create_Response_File
     (Format   : Response_File_Format;
      Objects  : String_List;
      Name     : out Path_Name_Type)
   is
      Resp_File : File_Descriptor;
      Status    : Integer;
      pragma Warnings (Off, Status);
      Closing_Status : Boolean;
      pragma Warnings (Off, Closing_Status);

   begin
      Tempdir.Create_Temp_File (Resp_File, Name => Name);
      Record_Temp_File (Name);

      if Format = GNU then
         Status := Write (Resp_File, GNU_Header'Address, GNU_Header'Length);
      end if;

      for J in Objects'Range loop
         if Format = GNU then
            Status :=
              Write (Resp_File, GNU_Opening'Address, GNU_Opening'Length);
         end if;

         Status :=
           Write (Resp_File, Objects (J).all'Address, Objects (J)'Length);

         if Format = GNU then
            Status :=
              Write (Resp_File, GNU_Closing'Address, GNU_Closing'Length);

         else
            Status :=
              Write (Resp_File, ASCII.LF'Address, 1);
         end if;
      end loop;

      if Format = GNU then
         Status :=
           Write (Resp_File, GNU_Footer'Address, GNU_Footer'Length);
      end if;

      Close (Resp_File, Closing_Status);
   end Create_Response_File;

   ------------------
   -- Fail_Program --
   ------------------

   procedure Fail_Program (S : String; Flush_Messages : Boolean := True) is
   begin
      if Flush_Messages then
         if Total_Errors_Detected /= 0 or else Warnings_Detected /= 0 then
            Errutil.Finalize;
         end if;
      end if;

      Finish_Program (Fatal => True, S => S);
   end Fail_Program;

   ----------------------------
   -- Find_Binding_Languages --
   ----------------------------

   procedure Find_Binding_Languages is
      B_Data : Binding_Data;

      Language_Name      : Name_Id;
      Binder_Driver_Name : File_Name_Type := No_File;
      Binder_Driver_Path : String_Access;
      Binder_Prefix      : Name_Id;
      Language           : Language_Ptr;

      Config : Language_Config;

      Compiler_Path : String_Access;
      Project : Project_List;
      Found : Boolean;

   begin
      There_Are_Binder_Drivers := False;

      Project := Project_Tree.Projects;
      while Project /= null loop
         Language := Project.Project.Languages;

         while Language /= No_Language_Index loop
            Config := Language.Config;

            Binder_Driver_Name := Config.Binder_Driver;

            if Language.First_Source /= No_Source
              and then Binder_Driver_Name /= No_File
            then
               There_Are_Binder_Drivers := True;
               Language_Name := Language.Name;

               Found := False;
               for B_Index in 1 .. Binding_Languages.Last loop
                  if Binding_Languages.Table (B_Index).Language_Name =
                    Language_Name
                  then
                     Found := True;
                     exit;
                  end if;
               end loop;

               if not Found then
                  Get_Name_String (Binder_Driver_Name);
                  Binder_Driver_Path :=
                    Locate_Exec_On_Path (Name_Buffer (1 .. Name_Len));

                  if Binder_Driver_Path = null then
                     Fail_Program
                       ("unable to find binder driver " &
                        Name_Buffer (1 .. Name_Len));
                  end if;

                  Compiler_Path := Config.Compiler_Driver_Path;

                  --  If this is the first time we try this compiler, then get
                  --  its path name.

                  if Compiler_Path = null then
                     declare
                        Compiler_Name : constant String :=
                          Get_Name_String
                            (Language.Config.Compiler_Driver);

                     begin
                        Compiler_Path := Locate_Exec_On_Path (Compiler_Name);

                        if Compiler_Path = null then
                           Fail_Program
                             ("unable to locate """ & Compiler_Name & '"');

                        else
                           Language.Config.Compiler_Driver_Path :=
                             Compiler_Path;
                        end if;
                     end;
                  end if;

                  if Config.Binder_Prefix = No_Name then
                     Binder_Prefix := Empty_String;

                  else
                     Binder_Prefix := Config.Binder_Prefix;
                  end if;

                  for B_Index in 1 .. Binding_Languages.Last loop
                     if Binder_Prefix =
                       Binding_Languages.Table (B_Index).Binder_Prefix
                     then
                        Fail_Program
                          ("binding prefix cannot be the same for"
                           & " two languages");
                     end if;
                  end loop;

                  B_Data :=
                    (Language           => Language,
                     Language_Name      => Language_Name,
                     Binder_Driver_Name => Binder_Driver_Name,
                     Binder_Driver_Path => Binder_Driver_Path,
                     Binder_Prefix      => Binder_Prefix);
                  Binding_Languages.Append (B_Data);
               end if;
            end if;

            Language := Language.Next;
         end loop;

         Project := Project.Next;
      end loop;
   end Find_Binding_Languages;

   --------------------
   -- Finish_Program --
   --------------------

   procedure Finish_Program (Fatal : Boolean; S : String := "") is
   begin
      if not Debug_Flag_N then
         Delete_All_Temp_Files;
      end if;

      if S'Length > 0 then
         if Fatal then
            Osint.Fail (S);

         else
            Write_Str (S);
         end if;
      end if;

      if Fatal then
         Exit_Program (E_Fatal);

      else
         Exit_Program (E_Success);
      end if;
   end Finish_Program;

   ---------------
   -- Get_Mains --
   ---------------

   procedure Get_Mains is
   begin
      --  If no mains are specified on the command line, check attribute
      --  Main in the main project.

      if Mains.Number_Of_Mains = 0 then
         declare
            List    : String_List_Id := Main_Project.Mains;
            Element : String_Element;

         begin
            --  The attribute Main is an empty list, so compile all the
            --  sources of the main project.

            if List /= Prj.Nil_String then
               --  The attribute Main is not an empty list.
               --  Get the mains in the list

               while List /= Prj.Nil_String loop
                  Element := Project_Tree.String_Elements.Table (List);

                  Get_Name_String (Element.Value);
                  Canonical_Case_File_Name (Name_Buffer (1 .. Name_Len));
                  Mains.Add_Main (Name_Buffer (1 .. Name_Len));
                  Mains.Set_Location (Element.Location);

                  List := Element.Next;
               end loop;
            end if;
         end;
      end if;

      --  If there are mains, check that they are sources of the main project

      if Mains.Number_Of_Mains > 0 then
         Mains.Reset;

         for J in 1 .. Mains.Number_Of_Mains loop
            declare
               Main     : String := Mains.Next_Main;
               Location : constant Source_Ptr := Mains.Get_Location;
               Main_Id  : File_Name_Type;
               Project  : Project_Id;
               Source   : Source_Id;
               Suffix   : File_Name_Type;
               Iter     : Source_Iterator;

            begin
               --  First, look for the main as specified

               Name_Len := 0;
               Add_Str_To_Name_Buffer (Main);
               Canonical_Case_File_Name (Name_Buffer (1 .. Name_Len));
               Main_Id := Name_Find;

               Project := Main_Project;
               while Project /= No_Project loop
                  Iter := For_Each_Source (Project_Tree, Project);
                  while Prj.Element (Iter) /= No_Source
                    and then Prj.Element (Iter).File /= Main_Id
                  loop
                     Next (Iter);
                  end loop;

                  Source := Prj.Element (Iter);
                  exit when Source /= No_Source;

                  Project := Project.Extends;
               end loop;

               if Source = No_Source then
                  --  Now look for the main with a body suffix

                  Canonical_Case_File_Name (Main);

                  Project := Main_Project;
                  loop
                     Iter := For_Each_Source (Project_Tree, Project);
                     loop
                        Source := Prj.Element (Iter);
                        exit when Source = No_Source;

                        --  Only consider bodies

                        if Source.Kind = Impl then
                           Get_Name_String (Source.File);

                           if Name_Len > Main'Length
                             and then Name_Buffer (1 .. Main'Length) = Main
                           then
                              Suffix :=
                                Source.Language
                                  .Config.Naming_Data.Body_Suffix;

                              exit when Suffix /= No_File and then
                              Name_Buffer (Main'Length + 1 .. Name_Len) =
                                Get_Name_String (Suffix);
                           end if;
                        end if;

                        Next (Iter);
                     end loop;

                     exit when Source /= No_Source;

                     Project := Project.Extends;

                     exit when Project = No_Project;
                  end loop;

                  if Source /= No_Source then
                     Mains.Update_Main (Name_Buffer (1 .. Name_Len));

                  elsif Location /= No_Location then
                     --  If the main is declared in package Builder of the
                     --  main project, report an error. If the main is on the
                     --  command line, it may be a main from another project,
                     --  so do nothing: if the main does not exist in another
                     --  project, an error will be reported later.

                     Error_Msg_File_1 := Main_Id;
                     Error_Msg_Name_1 := Main_Project.Name;
                     Errutil.Error_Msg ("{ is not a source of project %%",
                                        Location);
                  end if;
               end if;
            end;
         end loop;
      end if;

      if Total_Errors_Detected > 0 then
         Fail_Program ("problems with main sources");
      end if;
   end Get_Mains;

   ------------------------------
   -- Look_For_Default_Project --
   ------------------------------

   procedure Look_For_Default_Project is
   begin
      if Is_Regular_File (Default_Project_File_Name) then
         Project_File_Name := new String'(Default_Project_File_Name);

      else
         --  Check if there is a single project file in the current
         --  directory. If there is one and only one, use it.

         declare
            Dir : Dir_Type;
            Str : String (1 .. 255);
            Last : Natural;
            Single : String_Access := null;

         begin
            Open (Dir, ".");

            loop
               Read (Dir, Str, Last);
               exit when Last = 0;

               if Last > Project_File_Extension'Length and then
                 Is_Regular_File (Str (1 .. Last))
               then
                  Canonical_Case_File_Name (Str (1 .. Last));

                  if Str (Last - Project_File_Extension'Length + 1 .. Last)
                    = Project_File_Extension
                  then
                     if Single = null then
                        Single := new String'(Str (1 .. Last));

                     else
                        --  There are several project files in the current
                        --  directory. Reset Single to null and exit.

                        Single := null;
                        exit;
                     end if;
                  end if;
               end if;
            end loop;

            Close (Dir);

            Project_File_Name := Single;
         end;
      end if;

      if (not Quiet_Output) and then Project_File_Name /= null then
         Write_Str ("using project file ");
         Write_Line (Project_File_Name.all);
      end if;
   end Look_For_Default_Project;

   ------------------
   -- Partial_Name --
   ------------------

   function Partial_Name
     (Lib_Name      : String;
      Number        : Natural;
      Object_Suffix : String) return String
   is
      Img : constant String := Number'Img;
   begin
      return
        Partial_Prefix & Lib_Name &
        '_' & Img (Img'First + 1 .. Img'Last)
        & Object_Suffix;
   end Partial_Name;

   ----------------------
   -- Runtime_Name_For --
   ----------------------

   function Runtime_Name_For (Language : Name_Id) return String is
   begin
      if RTS_Languages.Get (Language) /= No_Name then
         return Get_Name_String (RTS_Languages.Get (Language));

      elsif RTS_Name /= null and then Language = Name_Ada then
         return RTS_Name.all;

      else
         return "";
      end if;
   end Runtime_Name_For;

   -------------------------
   -- Normalized_Hostname --
   -------------------------

   function Normalized_Hostname return String is
      Id : Targets_Set_Id;
   begin
      Get_Targets_Set (Base, Hostname, Id);
      return Normalized_Target (Base, Id);
   end Normalized_Hostname;

end Gpr_Util;
