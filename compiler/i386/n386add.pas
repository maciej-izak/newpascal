{
    Copyright (c) 2000-2002 by Florian Klaempfl

    Code generation for add nodes on the i386

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}
unit n386add;

{$i fpcdefs.inc}

interface

    uses
       node,nadd,cpubase,nx86add;

    type
       ti386addnode = class(tx86addnode)
{$ifdef SUPPORT_MMX}
          procedure second_addmmxset;override;
          procedure second_addmmx;override;
{$endif SUPPORT_MMX}
          procedure second_add64bit;override;
          procedure second_cmp64bit;override;
          procedure second_mul;override;
       end;

  implementation

    uses
      globtype,systems,
      cutils,verbose,globals,
      symconst,symdef,paramgr,
      aasmbase,aasmtai,aasmcpu,
      cgbase,
      ncon,nset,cgutils,tgobj,
      cga,ncgutil,cgobj,cg64f32;

{*****************************************************************************
                                   addmmxset
*****************************************************************************}

{$ifdef SUPPORT_MMX}
    procedure ti386addnode.second_addmmxset;

    var opsize : TCGSize;
        op     : TAsmOp;
        cmpop,
        pushedfpu,
        noswap : boolean;
    begin
      pass_left_and_right(pushedfpu);

      cmpop:=false;
      noswap:=false;
      opsize:=OS_32;
      case nodetype of
        addn:
          begin
            { are we adding set elements ? }
            if right.nodetype=setelementn then
              begin
                { adding elements is not commutative }
{                if nf_swaped in flags then
                  swapleftright;}
                { bts requires both elements to be registers }
{                location_force_reg(exprasmlist,left.location,opsize_2_cgsize[opsize],false);
                location_force_reg(exprasmlist,right.location,opsize_2_cgsize[opsize],true);
                op:=A_BTS;
                noswap:=true;}
              end
            else
              op:=A_POR;
          end;
        symdifn :
          op:=A_PXOR;
        muln:
          op:=A_PAND;
        subn:
          op:=A_PANDN;
        equaln,
        unequaln :
          begin
            op:=A_PCMPEQD;
            cmpop:=true;
          end;
        lten,gten:
          begin
            if (not(nf_swaped in flags) and (nodetype = lten)) or
               ((nf_swaped in flags) and (nodetype = gten)) then
              swapleftright;
            location_force_reg(exprasmlist,left.location,opsize,true);
            emit_op_right_left(A_AND,TCGSize2Opsize[opsize]);
            op:=A_PCMPEQD;
            cmpop:=true;
            { warning: ugly hack, we need a JE so change the node to equaln }
            nodetype:=equaln;
          end;
          xorn :
            op:=A_PXOR;
          orn :
            op:=A_POR;
          andn :
            op:=A_PAND;
          else
            internalerror(2003042215);
        end;
        { left must be a register }
        left_must_be_reg(opsize,noswap);
{        emit_generic_code(op,opsize,true,extra_not,false);}
        location_freetemp(exprasmlist,right.location);
        if cmpop then
          location_freetemp(exprasmlist,left.location);
        set_result_location(cmpop,true);
      end;
{$endif SUPPORT_MMX}


{*****************************************************************************
                                Add64bit
*****************************************************************************}

    procedure ti386addnode.second_add64bit;
      var
        op         : TOpCG;
        op1,op2    : TAsmOp;
        opsize     : TOpSize;
        hregister,
        hregister2 : tregister;
        hl4        : tasmlabel;
        mboverflow,
        unsigned:boolean;
        r:Tregister;
      begin
        firstcomplex(self);
        pass_left_right;

        op1:=A_NONE;
        op2:=A_NONE;
        mboverflow:=false;
        opsize:=S_L;
        unsigned:=((left.resulttype.def.deftype=orddef) and
                   (torddef(left.resulttype.def).typ=u64bit)) or
                  ((right.resulttype.def.deftype=orddef) and
                   (torddef(right.resulttype.def).typ=u64bit));
        case nodetype of
          addn :
            begin
              op:=OP_ADD;
              mboverflow:=true;
            end;
          subn :
            begin
              op:=OP_SUB;
              op1:=A_SUB;
              op2:=A_SBB;
              mboverflow:=true;
            end;
          xorn:
            op:=OP_XOR;
          orn:
            op:=OP_OR;
          andn:
            op:=OP_AND;
          else
            begin
              { everything should be handled in pass_1 (JM) }
              internalerror(200109051);
            end;
        end;

        { left and right no register?  }
        { then one must be demanded    }
        if (left.location.loc<>LOC_REGISTER) then
         begin
           if (right.location.loc<>LOC_REGISTER) then
            begin
              hregister:=cg.getintregister(exprasmlist,OS_INT);
              hregister2:=cg.getintregister(exprasmlist,OS_INT);
              cg64.a_load64_loc_reg(exprasmlist,left.location,joinreg64(hregister,hregister2));
              location_reset(left.location,LOC_REGISTER,OS_64);
              left.location.register64.reglo:=hregister;
              left.location.register64.reghi:=hregister2;
            end
           else
            begin
              location_swap(left.location,right.location);
              toggleflag(nf_swaped);
            end;
         end;

        { at this point, left.location.loc should be LOC_REGISTER }
        if right.location.loc=LOC_REGISTER then
         begin
           { when swapped another result register }
           if (nodetype=subn) and (nf_swaped in flags) then
            begin
              cg64.a_op64_reg_reg(exprasmlist,op,location.size,
                left.location.register64,
                right.location.register64);
              location_swap(left.location,right.location);
              toggleflag(nf_swaped);
            end
           else
            begin
              cg64.a_op64_reg_reg(exprasmlist,op,location.size,
                right.location.register64,
                left.location.register64);
            end;
         end
        else
         begin
           { right.location<>LOC_REGISTER }
           if (nodetype=subn) and (nf_swaped in flags) then
            begin
              r:=cg.getintregister(exprasmlist,OS_INT);
              cg64.a_load64low_loc_reg(exprasmlist,right.location,r);
              emit_reg_reg(op1,opsize,left.location.register64.reglo,r);
              emit_reg_reg(A_MOV,opsize,r,left.location.register64.reglo);
              cg64.a_load64high_loc_reg(exprasmlist,right.location,r);
              { the carry flag is still ok }
              emit_reg_reg(op2,opsize,left.location.register64.reghi,r);
              emit_reg_reg(A_MOV,opsize,r,left.location.register64.reghi);
            end
           else
            begin
              cg64.a_op64_loc_reg(exprasmlist,op,location.size,right.location,
                left.location.register64);
            end;
          location_freetemp(exprasmlist,right.location);
         end;

        { only in case of overflow operations }
        { produce overflow code }
        { we must put it here directly, because sign of operation }
        { is in unsigned VAR!!                              }
        if mboverflow then
         begin
           if cs_check_overflow in aktlocalswitches  then
            begin
              objectlibrary.getlabel(hl4);
              if unsigned then
                cg.a_jmp_flags(exprasmlist,F_AE,hl4)
              else
                cg.a_jmp_flags(exprasmlist,F_NO,hl4);
              cg.a_call_name(exprasmlist,'FPC_OVERFLOW');
              cg.a_label(exprasmlist,hl4);
            end;
         end;

        location_copy(location,left.location);
      end;


    procedure ti386addnode.second_cmp64bit;
      var
        hregister,
        hregister2 : tregister;
        href       : treference;
        unsigned   : boolean;

      procedure firstjmp64bitcmp;

        var
           oldnodetype : tnodetype;

        begin
{$ifdef OLDREGVARS}
           load_all_regvars(exprasmlist);
{$endif OLDREGVARS}
           { the jump the sequence is a little bit hairy }
           case nodetype of
              ltn,gtn:
                begin
                   cg.a_jmp_flags(exprasmlist,getresflags(unsigned),truelabel);
                   { cheat a little bit for the negative test }
                   toggleflag(nf_swaped);
                   cg.a_jmp_flags(exprasmlist,getresflags(unsigned),falselabel);
                   toggleflag(nf_swaped);
                end;
              lten,gten:
                begin
                   oldnodetype:=nodetype;
                   if nodetype=lten then
                     nodetype:=ltn
                   else
                     nodetype:=gtn;
                   cg.a_jmp_flags(exprasmlist,getresflags(unsigned),truelabel);
                   { cheat for the negative test }
                   if nodetype=ltn then
                     nodetype:=gtn
                   else
                     nodetype:=ltn;
                   cg.a_jmp_flags(exprasmlist,getresflags(unsigned),falselabel);
                   nodetype:=oldnodetype;
                end;
              equaln:
                cg.a_jmp_flags(exprasmlist,F_NE,falselabel);
              unequaln:
                cg.a_jmp_flags(exprasmlist,F_NE,truelabel);
           end;
        end;

      procedure secondjmp64bitcmp;

        begin
           { the jump the sequence is a little bit hairy }
           case nodetype of
              ltn,gtn,lten,gten:
                begin
                   { the comparisaion of the low dword have to be }
                   {  always unsigned!                            }
                   cg.a_jmp_flags(exprasmlist,getresflags(true),truelabel);
                   cg.a_jmp_always(exprasmlist,falselabel);
                end;
              equaln:
                begin
                   cg.a_jmp_flags(exprasmlist,F_NE,falselabel);
                   cg.a_jmp_always(exprasmlist,truelabel);
                end;
              unequaln:
                begin
                   cg.a_jmp_flags(exprasmlist,F_NE,truelabel);
                   cg.a_jmp_always(exprasmlist,falselabel);
                end;
           end;
        end;

      begin
        firstcomplex(self);

        pass_left_right;

        unsigned:=((left.resulttype.def.deftype=orddef) and
                   (torddef(left.resulttype.def).typ=u64bit)) or
                  ((right.resulttype.def.deftype=orddef) and
                   (torddef(right.resulttype.def).typ=u64bit));

        { left and right no register?  }
        { then one must be demanded    }
        if (left.location.loc<>LOC_REGISTER) then
         begin
           if (right.location.loc<>LOC_REGISTER) then
            begin
              { we can reuse a CREGISTER for comparison }
              if (left.location.loc<>LOC_CREGISTER) then
               begin
                 hregister:=cg.getintregister(exprasmlist,OS_INT);
                 hregister2:=cg.getintregister(exprasmlist,OS_INT);
                 cg64.a_load64_loc_reg(exprasmlist,left.location,joinreg64(hregister,hregister2));
                 location_reset(left.location,LOC_REGISTER,OS_64);
                 left.location.register64.reglo:=hregister;
                 left.location.register64.reghi:=hregister2;
               end;
            end
           else
            begin
              location_swap(left.location,right.location);
              toggleflag(nf_swaped);
            end;
         end;

        { at this point, left.location.loc should be LOC_REGISTER }
        if right.location.loc=LOC_REGISTER then
         begin
           emit_reg_reg(A_CMP,S_L,right.location.register64.reghi,left.location.register64.reghi);
           firstjmp64bitcmp;
           emit_reg_reg(A_CMP,S_L,right.location.register64.reglo,left.location.register64.reglo);
           secondjmp64bitcmp;
         end
        else
         begin
           case right.location.loc of
             LOC_CREGISTER :
               begin
                 emit_reg_reg(A_CMP,S_L,right.location.register64.reghi,left.location.register64.reghi);
                 firstjmp64bitcmp;
                 emit_reg_reg(A_CMP,S_L,right.location.register64.reglo,left.location.register64.reglo);
                 secondjmp64bitcmp;
               end;
             LOC_CREFERENCE,
             LOC_REFERENCE :
               begin
                 href:=right.location.reference;
                 inc(href.offset,4);
                 emit_ref_reg(A_CMP,S_L,href,left.location.register64.reghi);
                 firstjmp64bitcmp;
                 emit_ref_reg(A_CMP,S_L,right.location.reference,left.location.register64.reglo);
                 secondjmp64bitcmp;
                 cg.a_jmp_always(exprasmlist,falselabel);
                 location_freetemp(exprasmlist,right.location);
               end;
             LOC_CONSTANT :
               begin
                 exprasmlist.concat(taicpu.op_const_reg(A_CMP,S_L,aint(hi(right.location.value64)),left.location.register64.reghi));
                 firstjmp64bitcmp;
                 exprasmlist.concat(taicpu.op_const_reg(A_CMP,S_L,aint(lo(right.location.value64)),left.location.register64.reglo));
                 secondjmp64bitcmp;
               end;
             else
               internalerror(200203282);
           end;
         end;

        location_freetemp(exprasmlist,left.location);

        { we have LOC_JUMP as result }
        location_reset(location,LOC_JUMP,OS_NO)
      end;


{*****************************************************************************
                                AddMMX
*****************************************************************************}

{$ifdef SUPPORT_MMX}
    procedure ti386addnode.second_addmmx;
      var
        op         : TAsmOp;
        pushedfpu,
        cmpop      : boolean;
        mmxbase    : tmmxtype;
        hreg,
        hregister  : tregister;
      begin
        pass_left_and_right(pushedfpu);

        cmpop:=false;
        mmxbase:=mmx_type(left.resulttype.def);
        case nodetype of
          addn :
            begin
              if (cs_mmx_saturation in aktlocalswitches) then
                begin
                   case mmxbase of
                      mmxs8bit:
                        op:=A_PADDSB;
                      mmxu8bit:
                        op:=A_PADDUSB;
                      mmxs16bit,mmxfixed16:
                        op:=A_PADDSB;
                      mmxu16bit:
                        op:=A_PADDUSW;
                   end;
                end
              else
                begin
                   case mmxbase of
                      mmxs8bit,mmxu8bit:
                        op:=A_PADDB;
                      mmxs16bit,mmxu16bit,mmxfixed16:
                        op:=A_PADDW;
                      mmxs32bit,mmxu32bit:
                        op:=A_PADDD;
                   end;
                end;
            end;
          muln :
            begin
               case mmxbase of
                  mmxs16bit,mmxu16bit:
                    op:=A_PMULLW;
                  mmxfixed16:
                    op:=A_PMULHW;
               end;
            end;
          subn :
            begin
              if (cs_mmx_saturation in aktlocalswitches) then
                begin
                   case mmxbase of
                      mmxs8bit:
                        op:=A_PSUBSB;
                      mmxu8bit:
                        op:=A_PSUBUSB;
                      mmxs16bit,mmxfixed16:
                        op:=A_PSUBSB;
                      mmxu16bit:
                        op:=A_PSUBUSW;
                   end;
                end
              else
                begin
                   case mmxbase of
                      mmxs8bit,mmxu8bit:
                        op:=A_PSUBB;
                      mmxs16bit,mmxu16bit,mmxfixed16:
                        op:=A_PSUBW;
                      mmxs32bit,mmxu32bit:
                        op:=A_PSUBD;
                   end;
                end;
            end;
          xorn:
            op:=A_PXOR;
          orn:
            op:=A_POR;
          andn:
            op:=A_PAND;
          else
            internalerror(2003042214);
        end;

        { left and right no register?  }
        { then one must be demanded    }
        if (left.location.loc<>LOC_MMXREGISTER) then
         begin
           if (right.location.loc=LOC_MMXREGISTER) then
            begin
              location_swap(left.location,right.location);
              toggleflag(nf_swaped);
            end
           else
            begin
              { register variable ? }
              if (left.location.loc=LOC_CMMXREGISTER) then
               begin
                 hregister:=cg.getmmxregister(exprasmlist,OS_M64);
                 emit_reg_reg(A_MOVQ,S_NO,left.location.register,hregister);
               end
              else
               begin
                 if not(left.location.loc in [LOC_REFERENCE,LOC_CREFERENCE]) then
                  internalerror(200203245);

                 hregister:=cg.getmmxregister(exprasmlist,OS_M64);
                 emit_ref_reg(A_MOVQ,S_NO,left.location.reference,hregister);
               end;

              location_reset(left.location,LOC_MMXREGISTER,OS_NO);
              left.location.register:=hregister;
            end;
         end;

        { at this point, left.location.loc should be LOC_MMXREGISTER }
        if right.location.loc<>LOC_MMXREGISTER then
         begin
           if (nodetype=subn) and (nf_swaped in flags) then
            begin
              if right.location.loc=LOC_CMMXREGISTER then
               begin
                 hreg:=cg.getmmxregister(exprasmlist,OS_M64);
                 emit_reg_reg(A_MOVQ,S_NO,right.location.register,hreg);
                 emit_reg_reg(op,S_NO,left.location.register,hreg);
                 cg.ungetregister(exprasmlist,hreg);
                 emit_reg_reg(A_MOVQ,S_NO,hreg,left.location.register);
               end
              else
               begin
                 if not(left.location.loc in [LOC_REFERENCE,LOC_CREFERENCE]) then
                  internalerror(200203247);
                 hreg:=cg.getmmxregister(exprasmlist,OS_M64);
                 emit_ref_reg(A_MOVQ,S_NO,right.location.reference,hreg);
                 emit_reg_reg(op,S_NO,left.location.register,hreg);
                 cg.ungetregister(exprasmlist,hreg);
                 emit_reg_reg(A_MOVQ,S_NO,hreg,left.location.register);
               end;
            end
           else
            begin
              if (right.location.loc=LOC_CMMXREGISTER) then
                emit_reg_reg(op,S_NO,right.location.register,left.location.register)
              else
               begin
                 if not(right.location.loc in [LOC_REFERENCE,LOC_CREFERENCE]) then
                  internalerror(200203246);
                 emit_ref_reg(op,S_NO,right.location.reference,left.location.register);
               end;
            end;
          end
        else
          begin
            { right.location=LOC_MMXREGISTER }
            if (nodetype=subn) and (nf_swaped in flags) then
             begin
               emit_reg_reg(op,S_NO,left.location.register,right.location.register);
               location_swap(left.location,right.location);
               toggleflag(nf_swaped);
             end
            else
             begin
               emit_reg_reg(op,S_NO,right.location.register,left.location.register);
             end;
          end;

        location_freetemp(exprasmlist,right.location);
        if cmpop then
          location_freetemp(exprasmlist,left.location);

        set_result_location(cmpop,true);
      end;
{$endif SUPPORT_MMX}


{*****************************************************************************
                                x86 MUL
*****************************************************************************}

    procedure ti386addnode.second_mul;

    var r:Tregister;
        hl4 : tasmlabel;

    begin
      {The location.register will be filled in later (JM)}
      location_reset(location,LOC_REGISTER,OS_INT);
      {Get a temp register and load the left value into it
       and free the location.}
      r:=cg.getintregister(exprasmlist,OS_INT);
      cg.a_load_loc_reg(exprasmlist,OS_INT,left.location,r);
      {Allocate EAX.}
      cg.getcpuregister(exprasmlist,NR_EAX);
      {Load the right value.}
      cg.a_load_loc_reg(exprasmlist,OS_INT,right.location,NR_EAX);
      {Also allocate EDX, since it is also modified by a mul (JM).}
      cg.getcpuregister(exprasmlist,NR_EDX);
      emit_reg(A_MUL,S_L,r);
      if cs_check_overflow in aktlocalswitches  then
       begin
         objectlibrary.getlabel(hl4);
         cg.a_jmp_flags(exprasmlist,F_AE,hl4);
         cg.a_call_name(exprasmlist,'FPC_OVERFLOW');
         cg.a_label(exprasmlist,hl4);
       end;
      {Free EAX,EDX}
      cg.ungetcpuregister(exprasmlist,NR_EDX);
      cg.ungetcpuregister(exprasmlist,NR_EAX);
      {Allocate a new register and store the result in EAX in it.}
      location.register:=cg.getintregister(exprasmlist,OS_INT);
      cg.a_load_reg_reg(exprasmlist,OS_INT,OS_INT,NR_EAX,location.register);
      location_freetemp(exprasmlist,left.location);
      location_freetemp(exprasmlist,right.location);
    end;


begin
   caddnode:=ti386addnode;
end.
