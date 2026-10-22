// Mode 3 only. Included after MultiGroupState and the group registry.
// Orders remain owned by the existing platform-specific execution helpers.
#ifdef __MQL5__
#define R3_TICKET ulong
#define R3_DIRECTION long
#else
#define R3_TICKET int
#define R3_DIRECTION int
#endif
#ifndef R3_SEND_MARKET_LEG
#define R3_SEND_MARKET_LEG MultiSendMarketLeg
#endif
#ifndef R3_EXECUTION_ERROR
#define R3_EXECUTION_ERROR R3LastExecutionError
#endif
#ifndef R3_STORE_VALUE
#define R3_STORE_VALUE GlobalVariableSet
#endif
#ifndef R3_NORMALIZE_VOLUME
#define R3_NORMALIZE_VOLUME VolumeNormalize
#endif
#ifndef R3_OPEN_INITIAL_REMAINDER
#define R3_OPEN_INITIAL_REMAINDER MultiOpenMarket
#endif

enum BasketRenewalPhase
  {
   R3_IDLE=0, R3_STOP_RECORDED=1, R3_PRIMARY_CONFIRMED=2,
   R3_NO_RENEWAL=3, R3_CHILD_RESERVED=4, R3_CHILD_IN_FLIGHT=5,
   R3_CHILD_PARTIAL=6, R3_PAIRED=7, R3_FAILED=8, R3_CANCELED=9
  };
struct BasketFamilyState
  {
   int serial, id, generation, first_id, second_id;
   int first_finished, second_finished, started_mask;
   int source_id, source_sequence, event_batch, peer_id, peer_finished;
   int old_index, target_index, old_reversals;
   double target_loss;
   int direction, stop_points, take_profit_points, cycle_mode;
   double target_lots, confirmed_lots;
   int child_id, phase, request_pending, attempts, failure_code;
   double volume_before;
   datetime retry_after;
   ulong source_entry_cursor;
   double grid_before;
  };
BasketFamilyState g_basket_families[];
int g_basket_renewal_batch=0;
bool g_basket_renewal_storage_fault=false;
int g_basket_next_id_floor=1;

bool IsPairedBasketMode() { return 篮子数量==2 || 篮子数量==3; }
int R3LastExecutionError()
  {
#ifdef __MQL5__
   return (int)g_trade.ResultRetcode();
#else
   return g_multi_last_send_error;
#endif
  }
int R3GroupIndex(const int id)
  {
   for(int i=0;i<ArraySize(g_multi_groups);i++) if(g_multi_groups[i].id==id) return i;
   return -1;
  }
int R3FamilyIndex(const int id)
  {
   for(int i=0;i<ArraySize(g_basket_families);i++) if(g_basket_families[i].id==id) return i;
   return -1;
  }
string R3ScopeForState(const string state_prefix)
  {
#ifdef __MQL5__
   return AccountInfoString(ACCOUNT_SERVER)+"|"+Symbol()+"|"+state_prefix;
#else
   return AccountServer()+"|"+Symbol()+"|"+state_prefix;
#endif
  }
string R3Scope() {return R3ScopeForState(StatePrefix());}
ulong R3Magic()
  {
#ifdef __MQL5__
   return g_gui_applied_config.magic_number;
#else
   return (ulong)InpMagicNumber;
#endif
  }
string R3PrefixForState(const string state_prefix)
  {
   const string scope=R3ScopeForState(state_prefix);uint a=2166136261,b=2246822519;
   for(int i=0;i<StringLen(scope);i++)
     {const uint c=(uint)StringGetCharacter(scope,i);a=(a^c)*16777619;b=(b+c)*3266489917;}
   return "NMR3."+StringFormat("%08X%08X",a,b);
  }
string R3Prefix() {return R3PrefixForState(StatePrefix());}
string BasketRenewalConfigPrefix(const string state_prefix)
  {
   const string compact=R3PrefixForState(state_prefix);
   if(!GlobalVariableCheck(compact+".cfgok") || GlobalVariableGet(compact+".cfgok")!=1)return state_prefix;
   const string scope=R3ScopeForState(state_prefix),base=compact+".s.";
   if(!GlobalVariableCheck(base+"n") || GlobalVariableGet(base+"n")!=StringLen(scope))return state_prefix;
   for(int i=0;i<StringLen(scope);i++)
      if(!GlobalVariableCheck(base+IntegerToString(i))
         || GlobalVariableGet(base+IntegerToString(i))!=StringGetCharacter(scope,i))return state_prefix;
   return compact+".cfg";
  }
bool R3SaveConfig()
  {
#ifdef __MQL5__
   const string prefix=R3Prefix()+".cfg";
   if(!R3Put(R3Prefix()+".cfgok",0))return false;GlobalVariablesFlush();
#ifdef NMR_RENEWAL_CORE
   if(!R3Put(prefix+".owner.profile",NMR_FIXED_PROFILE_ID)
      || !R3Put(prefix+".owner.schema",1))return false;
#endif
   if(!R3Put(prefix+".configfingerprint",GuiConfigFingerprint(g_gui_applied_config))
      || !R3Put(prefix+".configfingerprint2",GuiConfigFingerprint2(g_gui_applied_config)))return false;
   GlobalVariablesFlush();if(!R3Put(R3Prefix()+".cfgok",1))return false;GlobalVariablesFlush();
#endif
   return true;
  }
string R3GroupPrefix(const int id) {return R3Prefix()+".g."+IntegerToString(id);}
bool R3EnsureScope()
  {
   const string scope=R3Scope(),base=R3Prefix()+".s.";
   if(GlobalVariableCheck(base+"n"))
     {
      if(GlobalVariableGet(base+"n")!=StringLen(scope)) {g_basket_renewal_storage_fault=true;return false;}
      for(int i=0;i<StringLen(scope);i++)
         if(!GlobalVariableCheck(base+IntegerToString(i))
            || GlobalVariableGet(base+IntegerToString(i))!=StringGetCharacter(scope,i))
           {g_basket_renewal_storage_fault=true;return false;}
      return true;
     }
   for(int i=0;i<StringLen(scope);i++)
      if(!R3Put(base+IntegerToString(i),StringGetCharacter(scope,i)))return false;
   GlobalVariablesFlush();return R3Put(base+"n",StringLen(scope));
  }
double R3Tolerance()
  {
#ifdef __MQL5__
   const double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
#else
   const double step=MarketInfo(Symbol(),MODE_LOTSTEP);
#endif
   return step>0 ? step*0.5 : 0.0000001;
  }
void R3Encode(const BasketFamilyState &f,double &v[])
  {
   ArrayResize(v,34);
   v[0]=2; v[1]=f.serial; v[2]=f.id; v[3]=f.generation;
   v[4]=f.first_id; v[5]=f.second_id; v[6]=f.first_finished;
   v[7]=f.second_finished; v[8]=f.started_mask; v[9]=f.source_id;
   v[10]=f.source_sequence; v[11]=f.event_batch; v[12]=f.peer_id;
   v[13]=f.peer_finished; v[14]=f.old_index; v[15]=f.target_index;
   v[16]=f.old_reversals; v[17]=f.target_loss; v[18]=f.direction;
   v[19]=f.stop_points; v[20]=f.take_profit_points; v[21]=f.cycle_mode;
   v[22]=f.target_lots; v[23]=f.confirmed_lots; v[24]=f.child_id;
   v[25]=f.phase; v[26]=f.request_pending; v[27]=f.attempts;
   v[28]=f.failure_code; v[29]=f.volume_before; v[30]=(double)f.retry_after;
   v[31]=(double)(f.source_entry_cursor>>32);v[32]=(double)(f.source_entry_cursor & (ulong)0xFFFFFFFF);
   v[33]=f.grid_before;
  }
bool R3Decode(const double &v[],BasketFamilyState &f)
  {
   if(ArraySize(v)!=34 || v[0]!=2 || v[1]<=0 || v[2]<=0) return false;
   f.serial=(int)v[1]; f.id=(int)v[2]; f.generation=(int)v[3];
   f.first_id=(int)v[4]; f.second_id=(int)v[5]; f.first_finished=(int)v[6];
   f.second_finished=(int)v[7]; f.started_mask=(int)v[8]; f.source_id=(int)v[9];
   f.source_sequence=(int)v[10]; f.event_batch=(int)v[11]; f.peer_id=(int)v[12];
   f.peer_finished=(int)v[13]; f.old_index=(int)v[14]; f.target_index=(int)v[15];
   f.old_reversals=(int)v[16]; f.target_loss=v[17]; f.direction=(int)v[18];
   f.stop_points=(int)v[19]; f.take_profit_points=(int)v[20]; f.cycle_mode=(int)v[21];
   f.target_lots=v[22]; f.confirmed_lots=v[23]; f.child_id=(int)v[24];
   f.phase=(int)v[25]; f.request_pending=(int)v[26]; f.attempts=(int)v[27];
   f.failure_code=(int)v[28]; f.volume_before=v[29]; f.retry_after=(datetime)v[30];
   f.source_entry_cursor=((ulong)v[31]<<32) | (ulong)v[32];
   f.grid_before=v[33];
   return f.first_id>0 && f.second_id>0 && f.phase>=0 && f.phase<=9;
  }
bool R3Put(const string key,const double value)
  {
   if(StringLen(key)>63 || R3_STORE_VALUE(key,value)==0)
     { g_basket_renewal_storage_fault=true; Print("[R3_STORAGE_FAILED] ",key); return false; }
   return true;
  }
bool R3Save(BasketFamilyState &f)
  {
   if(g_basket_renewal_storage_fault || f.serial>=2147483646) return false;
   BasketFamilyState next=f; next.serial++;
   const string base=R3Prefix()+"."+IntegerToString(f.id)+"."+IntegerToString(next.serial%2);
   if(!R3Put(base+".ok",0)) return false;
   GlobalVariablesFlush();
   double v[]; R3Encode(next,v);
   for(int k=0;k<ArraySize(v);k++) if(!R3Put(base+"."+IntegerToString(k),v[k])) return false;
   GlobalVariablesFlush();
   if(!R3Put(base+".ok",next.serial)) return false;
   GlobalVariablesFlush();
   f.serial=next.serial;
   const int index=R3FamilyIndex(f.id);
   if(index>=0) g_basket_families[index]=f;
   return true;
  }
bool R3Position(const int id,R3_TICKET &ticket,R3_DIRECTION &type,double &lots,
                double &entry,double &sl,double &tp)
  { return MultiFindPosition(id,ticket,type,lots,entry,sl,tp); }
bool R3HasPending(const int id)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
#ifdef __MQL5__
      const ulong ticket=OrderGetTicket(i);
      if(ticket>0 && OrderGetString(ORDER_SYMBOL)==_Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC)==R3Magic()
         && MultiCommentMatches(OrderGetString(ORDER_COMMENT),id)) return true;
#else
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderSymbol()==Symbol()
         && OrderMagicNumber()==InpMagicNumber && OrderType()>OP_SELL
         && MultiCommentMatches(OrderComment(),id)) return true;
#endif
     }
   return false;
  }
bool R3HasOpeningOrder(const int id)
  {
#ifdef __MQL5__
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      const ulong ticket=OrderGetTicket(i);
      if(ticket>0 && OrderGetString(ORDER_SYMBOL)==_Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC)==R3Magic()
         && OrderGetInteger(ORDER_TYPE)<=ORDER_TYPE_SELL
         && MultiCommentMatches(OrderGetString(ORDER_COMMENT),id))return true;
     }
#endif
   return false;
  }
bool R3CancelOutstandingOrders(const int id)
  {
#ifdef __MQL5__
   bool canceled=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      const ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC)!=R3Magic()
         || !MultiCommentMatches(OrderGetString(ORDER_COMMENT),id))continue;
      // RETURN market remainders also occupy an order; do not filter by
      // reverse/grid pending type when canceling a mode3 opening intent.
      if(!g_trade.OrderDelete(ticket))canceled=false;
     }
   return canceled && !R3HasPending(id);
#else
   return MultiDeletePending(id) && !R3HasPending(id);
#endif
  }
bool R3RequestUnknown(const MultiGroupState &group)
  {
   if(group.renewal_request_state==1) return true;
#ifdef __MQL5__
   if(group.request_in_flight) return true;
#ifdef NMR_RENEWAL_CORE
   if(group.request_reconcile_quarantine) return true;
#endif
#else
#ifdef NMR_RENEWAL_CORE
   if(group.market_request_unresolved) return true;
#endif
   if(group.launch_attempted) return true;
#endif
   return false;
  }
bool R3HistoryShowsEntry(const int id)
  {
#ifdef __MQL5__
   if(!HistorySelect(0,TimeCurrent()+1)) return false;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      const ulong deal=HistoryDealGetTicket(i);
      if(deal>0 && HistoryDealGetString(deal,DEAL_SYMBOL)==_Symbol
         && (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)==R3Magic()
         && HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN
         && MultiCommentMatches(HistoryDealGetString(deal,DEAL_COMMENT),id)) return true;
     }
#else
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderSymbol()==Symbol()
         && OrderMagicNumber()==InpMagicNumber && OrderType()<=OP_SELL
         && MultiCommentMatches(OrderComment(),id)) return true;
#endif
   return false;
  }
bool R3HasDurableAttempt(const MultiGroupState &group)
  {
   const string key=MultiStatePrefix(group.id)+".rrcommit";
   // A cleared/prepared current leg supersedes lifetime platform request counters.
   if(GlobalVariableCheck(key))
      return GlobalVariableGet(key)>0.5 && group.renewal_request_state!=0;
   if(group.renewal_request_state!=0) return true;
#ifdef __MQL5__
   return group.request_signal_id!=0 || group.request_in_flight || group.request_order_ticket>0;
#else
#ifdef NMR_RENEWAL_CORE
   return group.market_request_sequence>0 || group.market_request_unresolved;
#else
   return group.launch_attempted || group.launch_attempt_count>0;
#endif
#endif
  }
void R3ClearRequest(MultiGroupState &group)
  {
   group.renewal_request_state=0;
#ifdef __MQL5__
   group.request_in_flight=false;
#ifdef NMR_RENEWAL_CORE
   group.request_reconcile_quarantine=false;
#endif
#else
   group.launch_attempted=false;
#ifdef NMR_RENEWAL_CORE
   group.market_request_unresolved=false;
#endif
#endif
   group.dirty=true;
  }
bool R3PrepareNextLeg(MultiGroupState &group)
  {
   ulong cursor=0;if(!R3EntryCursor(group.id,cursor))return false;
   if(!R3Put(MultiStatePrefix(group.id)+".rrcommit",0))return false;
   GlobalVariablesFlush();
   R3ClearRequest(group);group.renewal_deal_cursor=cursor;
   MultiSaveGroup(group);GlobalVariablesFlush();
   const int i=R3GroupIndex(group.id);if(i>=0)g_multi_groups[i]=group;
   return true;
  }
bool R3EntryCursor(const int id,ulong &cursor,const int direction=-1)
  {
   cursor=0;
#ifdef __MQL5__
   // Include deals with millisecond timestamps later within the current second.
   if(!HistorySelect(0,TimeCurrent()+1)) return false;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      const ulong ticket=HistoryDealGetTicket(i);
      if(ticket>cursor && HistoryDealGetString(ticket,DEAL_SYMBOL)==_Symbol
         && (ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)==R3Magic()
         && HistoryDealGetInteger(ticket,DEAL_ENTRY)==DEAL_ENTRY_IN
         && (direction<0 || HistoryDealGetInteger(ticket,DEAL_TYPE)==direction)
         && MultiCommentMatches(HistoryDealGetString(ticket,DEAL_COMMENT),id)) cursor=ticket;
     }
#else
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderSymbol()==Symbol()
         && OrderMagicNumber()==InpMagicNumber && OrderType()<=OP_SELL
         && (direction<0 || OrderType()==direction)
         && MultiCommentMatches(OrderComment(),id)) cursor=(ulong)MathMax((double)cursor,OrderTicket());
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderSymbol()==Symbol()
         && OrderMagicNumber()==InpMagicNumber && OrderType()<=OP_SELL
         && (direction<0 || OrderType()==direction)
         && MultiCommentMatches(OrderComment(),id)) cursor=(ulong)MathMax((double)cursor,OrderTicket());
#endif
   return true;
  }
double R3DirectionVolume(const int id,const int direction)
  {
#ifdef __MQL5__
   return MultiTotalPositionVolume(id,(long)direction);
#else
   return MultiTotalLots(id,direction);
#endif
  }
bool BasketRenewalBeforeLeg(MultiGroupState &group,const int direction)
  {
   if(group.basket_mode_at_start!=3) return true;
   if(group.renewal_request_state==1 || g_basket_renewal_storage_fault || R3HasOpeningOrder(group.id)) return false;
   ulong cursor=0;if(!R3EntryCursor(group.id,cursor)) return false;
   const string prefix=MultiStatePrefix(group.id);
   if(!R3Put(prefix+".rrcommit",0)) return false;GlobalVariablesFlush();
   group.renewal_deal_cursor=cursor;group.renewal_request_direction=direction;
   group.renewal_request_volume_before=R3DirectionVolume(group.id,direction);
#ifdef __MQL5__
   group.request_order_ticket=0; // previous leg's order is never evidence for this leg
#endif
   group.renewal_request_state=1;group.dirty=true;MultiSaveGroup(group);GlobalVariablesFlush();
   if(!GlobalVariableCheck(prefix+".rrs") || GlobalVariableGet(prefix+".rrs")!=1
      || !GlobalVariableCheck(prefix+".rhi") || !GlobalVariableCheck(prefix+".rlo")
      || !GlobalVariableCheck(prefix+".rrd") || !GlobalVariableCheck(prefix+".rrv")
      || GlobalVariableGet(prefix+".rhi")!=(double)(cursor>>32)
      || GlobalVariableGet(prefix+".rlo")!=(double)(cursor & (ulong)0xFFFFFFFF)
      || GlobalVariableGet(prefix+".rrd")!=direction
      || GlobalVariableGet(prefix+".rrv")!=group.renewal_request_volume_before)
     {g_basket_renewal_storage_fault=true;return false;}
   if(!R3Put(prefix+".rrcommit",1)) return false;GlobalVariablesFlush();
   const int i=R3GroupIndex(group.id);if(i>=0)g_multi_groups[i]=group;
   return true;
  }
void BasketRenewalAfterLeg(MultiGroupState &group,const bool sent,const int error)
  {
   if(group.basket_mode_at_start!=3) return;
   const bool ambiguous=error==128 || error==6 || error==1 || error==10012 || error==10031;
   if(!sent && !ambiguous) group.renewal_request_state=3;
   else if(sent && R3DirectionVolume(group.id,group.renewal_request_direction)
         >group.renewal_request_volume_before+R3Tolerance()) group.renewal_request_state=2;
   group.dirty=true;MultiSaveGroup(group);GlobalVariablesFlush();
   const int i=R3GroupIndex(group.id);if(i>=0)g_multi_groups[i]=group;
  }
bool R3NewEntryAfterRequest(const MultiGroupState &group)
  {
   ulong cursor=0;
   return R3EntryCursor(group.id,cursor,group.renewal_request_direction) && cursor>group.renewal_deal_cursor;
  }
bool R3CurrentOrderCanceled(const MultiGroupState &group)
  {
#ifdef __MQL5__
   if(group.request_order_ticket==0 || !HistoryOrderSelect(group.request_order_ticket)
      || HistoryOrderGetString(group.request_order_ticket,ORDER_SYMBOL)!=_Symbol
      || (ulong)HistoryOrderGetInteger(group.request_order_ticket,ORDER_MAGIC)!=R3Magic()
      || !MultiCommentMatches(HistoryOrderGetString(group.request_order_ticket,ORDER_COMMENT),group.id))return false;
   const long state=HistoryOrderGetInteger(group.request_order_ticket,ORDER_STATE);
   return state==ORDER_STATE_CANCELED || state==ORDER_STATE_REJECTED || state==ORDER_STATE_EXPIRED;
#else
   return false;
#endif
  }
void BasketRenewalReconcileRequest(MultiGroupState &group)
  {
   if(group.basket_mode_at_start!=3 || group.renewal_request_state!=1) return;
   // A prior leg may already have closed, so net volume need not increase.
   // The current directional deal cursor proves acceptance; wait while a live
   // order can still deliver additional partial fills.
   if(!R3HasPending(group.id) && (R3NewEntryAfterRequest(group) || R3CurrentOrderCanceled(group)))
     {R3ClearRequest(group);MultiSaveGroup(group);}
  }
bool BasketRenewalResetIsPending()
  { return GlobalVariableCheck(R3Prefix()+".reset") && GlobalVariableGet(R3Prefix()+".reset")>0.5; }
bool BasketRenewalResetRequiresDeferral()
  {
   if(BasketRenewalResetIsPending() || BasketRenewalHasWork())return true;
   for(int i=0;i<ArraySize(g_multi_groups);i++)
      if(g_multi_groups[i].basket_mode_at_start==3)return true;
   return false;
  }
bool BasketRenewalDeferReset()
  {
   if(!BasketRenewalResetRequiresDeferral()) return false;
   R3Put(R3Prefix()+".reset",1);GlobalVariablesFlush();
   bool unknown=false;
   const int error=R3LastExecutionError();
   for(int i=0;i<ArraySize(g_basket_families);i++)
     {
      BasketFamilyState f=g_basket_families[i];f.phase=R3_CANCELED;
      // A definitive no-money rejection cannot become a late accepted request.
      if(error==10019 || error==134) f.request_pending=0;
      if(f.request_pending) unknown=true;
      R3Save(f);
     }
   for(int i=0;i<ArraySize(g_multi_groups);i++)
      if(g_multi_groups[i].basket_mode_at_start==3
         && (R3RequestUnknown(g_multi_groups[i]) || R3HasPending(g_multi_groups[i].id))) unknown=true;
   return unknown || HasOurPosition() || HasOurPending();
  }
bool BasketRenewalResetReady()
  {
   if(!BasketRenewalResetIsPending()) return true;
   bool unknown=false;
   for(int i=0;i<ArraySize(g_multi_groups);i++)
     {
      if(g_multi_groups[i].basket_mode_at_start!=3) continue;
      MultiGroupState group=g_multi_groups[i];
      if(R3HasPending(group.id) && !R3CancelOutstandingOrders(group.id))
        {unknown=true;continue;}
      BasketRenewalReconcileRequest(group);
      const int n=R3FamilyIndex(group.basket_family_id);
      R3_TICKET t=0;R3_DIRECTION d=0;double v=0,e=0,sl=0,tp=0;
      const bool live=R3Position(group.id,t,d,v,e,sl,tp);
      const bool accepted_closed=!live && !R3HasPending(group.id) && R3NewEntryAfterRequest(group);
      const bool current_request_resolved=group.renewal_request_state==2 || group.renewal_request_state==3
         || (group.renewal_request_state==1 && (accepted_closed
            || (live && R3DirectionVolume(group.id,group.renewal_request_direction)
               >group.renewal_request_volume_before+R3Tolerance())));
      if(current_request_resolved) R3ClearRequest(group);
      if(n>=0)
        {
         BasketFamilyState f=g_basket_families[n];
         if(f.child_id==group.id && f.request_pending)
           {
            if(live || accepted_closed || !R3HasDurableAttempt(group)) f.request_pending=0;
            else unknown=true;
            R3Save(f);
           }
        }
      if(R3RequestUnknown(group)) unknown=true;
      g_multi_groups[i]=group;MultiSaveGroup(g_multi_groups[i]);
     }
   if(unknown || HasOurPosition() || HasOurPending()) return false;
   MultiClearAll();
   R3Put(R3Prefix()+".reset",0);GlobalVariablesFlush();
   return true;
  }
bool BasketRenewalHasWork()
  {
   for(int i=0;i<ArraySize(g_basket_families);i++)
     {
      BasketFamilyState f=g_basket_families[i];
      if(!f.first_finished || !f.second_finished || f.request_pending) return true;
      if(f.phase==R3_STOP_RECORDED || f.phase==R3_PRIMARY_CONFIRMED
         || f.phase==R3_CHILD_RESERVED || f.phase==R3_CHILD_IN_FLIGHT
         || f.phase==R3_CHILD_PARTIAL) return true;
     }
   return false;
  }
void BasketRenewalLoad()
  {
   ArrayResize(g_basket_families,0);
   g_basket_renewal_storage_fault=false;
   if(GlobalVariableCheck(R3Prefix()+".s.n") && !R3EnsureScope()) return;
   const string prefix=R3Prefix()+".";
   const int total=GlobalVariablesTotal();
   for(int n=0;n<total;n++)
     {
      const string key=GlobalVariableName(n);
      if(StringFind(key,prefix)!=0) continue;
      const string tail=StringSubstr(key,StringLen(prefix));
      const int dot=StringFind(tail,"."); if(dot<1) continue;
      const int id=(int)StringToInteger(StringSubstr(tail,0,dot));
      if(id<=0 || R3FamilyIndex(id)>=0) continue;
      BasketFamilyState best; ZeroMemory(best);
      for(int slot=0;slot<2;slot++)
        {
         const string base=prefix+IntegerToString(id)+"."+IntegerToString(slot);
         if(!GlobalVariableCheck(base+".ok")) continue;
         const double valid=GlobalVariableGet(base+".ok");
         double v[]; ArrayResize(v,34); bool complete=valid>0;
         for(int k=0;k<34;k++)
           {
            const string field=base+"."+IntegerToString(k);
            if(!GlobalVariableCheck(field)) {complete=false;break;}
            v[k]=GlobalVariableGet(field);
           }
         BasketFamilyState loaded; ZeroMemory(loaded);
         if(complete && R3Decode(v,loaded) && loaded.id==id
            && loaded.serial==valid && loaded.serial>best.serial) best=loaded;
        }
      if(best.serial==0) {g_basket_renewal_storage_fault=true;continue;}
      const int size=ArraySize(g_basket_families);
      if(ArrayResize(g_basket_families,size+1)!=size+1) {g_basket_renewal_storage_fault=true;break;}
      g_basket_families[size]=best;
      g_multi_next_id=(int)MathMax(g_multi_next_id,MathMax(best.child_id,MathMax(best.first_id,best.second_id))+1);
      g_basket_renewal_batch=(int)MathMax(g_basket_renewal_batch,best.event_batch);
     }
   if(GlobalVariableCheck(R3Prefix()+".batch"))
      g_basket_renewal_batch=(int)MathMax(g_basket_renewal_batch,GlobalVariableGet(R3Prefix()+".batch"));
   if(GlobalVariableCheck(R3Prefix()+".next"))
      g_multi_next_id=(int)MathMax(g_multi_next_id,GlobalVariableGet(R3Prefix()+".next"));
   g_basket_next_id_floor=g_multi_next_id;
   if(BasketRenewalResetIsPending()) g_reset_pending=true;
   for(int i=0;i<ArraySize(g_basket_families);i++) R3RestoreSource(g_basket_families[i]);
#ifdef __MQL5__
   if(BasketRenewalHasWork() && AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      g_basket_renewal_storage_fault=true;
#endif
  }
bool BasketRenewalRegisterPair(const int mode,const int family_id,const int first_id,const int second_id)
  {
   if(mode!=3) return true;
   const int a=R3GroupIndex(first_id), b=R3GroupIndex(second_id);
   if(a<0 || b<0 || g_basket_renewal_storage_fault || !R3EnsureScope() || !R3SaveConfig()) return false;
   BasketFamilyState f; ZeroMemory(f);
   f.id=family_id; f.first_id=first_id; f.second_id=second_id;
   const int index=ArraySize(g_basket_families);
   if(ArrayResize(g_basket_families,index+1)!=index+1) return false;
   g_basket_families[index]=f;
   for(int j=0;j<2;j++)
     {
      const int i=j==0 ? a : b;
      g_multi_groups[i].basket_mode_at_start=3;
      g_multi_groups[i].basket_family_id=family_id;
      g_multi_groups[i].dirty=true; MultiSaveGroup(g_multi_groups[i]);
     }
   if(!R3Put(R3Prefix()+".next",g_multi_next_id))return false;
   return R3Save(f);
  }
bool BasketRenewalInitialFailure(const int first_id,const int second_id)
  {
   const int a=R3GroupIndex(first_id),b=R3GroupIndex(second_id);
   if(a<0 || b<0 || g_multi_groups[a].basket_mode_at_start!=3) return false;
   const int n=R3FamilyIndex(g_multi_groups[a].basket_family_id);if(n<0)return false;
   BasketFamilyState f=g_basket_families[n];
   R3_TICKET t=0;R3_DIRECTION d=0;double v=0,e=0,sl=0,tp=0;
   const bool live=R3Position(first_id,t,d,v,e,sl,tp);
   if(R3RequestUnknown(g_multi_groups[a]) || R3HasPending(first_id) || R3HasPending(second_id)) return true;
   if(live)
     {
      R3InitializeChild(g_multi_groups[a],d,v,e);
      g_multi_groups[a].transition_target_lots=0;
      MultiSetStops(g_multi_groups[a],d);MultiSaveGroup(g_multi_groups[a]);
      f.started_mask|=1;
     }
   else {g_multi_groups[a].active=false;g_multi_groups[a].dirty=true;MultiSaveGroup(g_multi_groups[a]);f.first_finished=1;}
   g_multi_groups[b].active=false;g_multi_groups[b].transition_target_lots=0;
   g_multi_groups[b].dirty=true;MultiSaveGroup(g_multi_groups[b]);f.second_finished=1;
   if(!live) f.phase=R3_CANCELED;
   R3Save(f);return live;
  }
void BasketRenewalBeginBatch()
  {
   if(ArraySize(g_basket_families)==0) return;
   if(g_basket_renewal_batch>=2147483646) {g_basket_renewal_storage_fault=true;return;}
   g_basket_renewal_batch++;
   R3Put(R3Prefix()+".batch",g_basket_renewal_batch);
   for(int n=0;n<ArraySize(g_basket_families);n++)
     {
      BasketFamilyState f=g_basket_families[n]; int mask=f.started_mask;
      for(int side=0;side<2;side++)
        {
         const int i=R3GroupIndex(side==0 ? f.first_id : f.second_id);
         if(i>=0 && g_multi_groups[i].anchor_price>0 && g_multi_groups[i].first_lots>0)
            mask|=(side==0 ? 1 : 2);
        }
      if(mask!=f.started_mask) {f.started_mask=mask;R3Save(f);}
     }
  }
bool BasketRenewalRecordFinished(const MultiGroupState &group)
  {
   if(group.basket_mode_at_start!=3) return true;
   const int n=R3FamilyIndex(group.basket_family_id); if(n<0) return false;
   R3_TICKET ticket=0; R3_DIRECTION type=0; double lots=0,entry=0,sl=0,tp=0;
   if(R3Position(group.id,ticket,type,lots,entry,sl,tp) || R3HasPending(group.id)
      || R3RequestUnknown(group)) return false;
   BasketFamilyState f=g_basket_families[n];
   if(group.id==f.first_id)
     {f.first_finished=1; if(group.anchor_price>0 && group.first_lots>0) f.started_mask|=1;}
   if(group.id==f.second_id)
     {f.second_finished=1; if(group.anchor_price>0 && group.first_lots>0) f.started_mask|=2;}
   if(f.peer_id==group.id && f.event_batch==g_basket_renewal_batch) f.peer_finished=1;
   return R3Save(f);
  }
bool BasketRenewalPrepareStop(MultiGroupState &group,const int next_index,
                              const int direction,const double target_lots,
                              const ulong filled_position=0)
  {
   if(group.basket_mode_at_start!=3) return true;
   const int n=R3FamilyIndex(group.basket_family_id); if(n<0) return false;
   BasketFamilyState f=g_basket_families[n];
   if(f.source_id==group.id && f.old_index==group.cycle_index
      && f.target_index==next_index && f.source_sequence==group.stop_event_sequence
      && f.phase==R3_STOP_RECORDED) return true;
   if(group.stop_event_sequence>=2147483646) return false;
   group.stop_event_sequence++; group.dirty=true;
   if(f.child_id>0 && (f.request_pending || f.phase==R3_CHILD_RESERVED
      || f.phase==R3_CHILD_IN_FLIGHT || f.phase==R3_CHILD_PARTIAL))
     {f.phase=R3_CANCELED;R3Save(f);return false;}
   f.source_id=group.id; f.source_sequence=group.stop_event_sequence;
   f.event_batch=g_basket_renewal_batch;
   f.peer_id=group.id==f.first_id ? f.second_id : f.first_id;
   f.peer_finished=group.id==f.first_id ? f.second_finished : f.first_finished;
   f.old_index=group.cycle_index; f.target_index=next_index;
   f.old_reversals=group.reversal_count;
   if(!R3EntryCursor(group.id,f.source_entry_cursor)) return false;
   if(filled_position>0)
     {
#ifdef __MQL5__
      if(!PositionSelectByTicket(filled_position)) return false;
      const ulong identifier=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(!HistorySelectByPosition(identifier)) return false;
      ulong first=0;
      for(int i=0;i<HistoryDealsTotal();i++)
        {
         const ulong deal=HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN && (first==0 || deal<first)) first=deal;
        }
      if(first==0)return false;
      f.source_entry_cursor=first-1;
#else
      f.source_entry_cursor=filled_position-1;
#endif
     }
   f.grid_before=group.grid_lots;
   f.target_loss=group.cumulative_loss_lots+group.total_lots;
   ReversalLotPlan effective;
   if(!BuildReversalLotPlan(target_lots,effective) || effective.status==REVERSAL_LOT_RESTART_GROUP) return false;
   f.direction=direction;
   // Mirror the existing per-leg normalization and remaining-target calculation.
   // Normalizing the two planned halves independently can overstate an odd split.
   f.target_lots=0;
   const double raw_total=effective.first_lots+(effective.count==2 ? effective.second_lots : 0.0);
   // Existing execution may need several calls when a broker caps a single leg.
   // Keep its aggregate target and simulate its final step rounding, without a
   // plan.count cutoff that would drop the still-outstanding volume.
   for(int leg=0;f.target_lots+R3Tolerance()<raw_total;leg++)
     {
      const double requested=MathMin(leg%effective.count==0 ? effective.first_lots : effective.second_lots,
                                     raw_total-f.target_lots);
      const double normalized=R3_NORMALIZE_VOLUME(requested);
      if(normalized<=0 || leg>=100000)return false;
      f.target_lots+=normalized;
     }
   if(f.target_lots<=0)return false;
   f.confirmed_lots=0;
   f.stop_points=group.stop_points; f.take_profit_points=group.take_profit_points;
   f.cycle_mode=group.cycle_mode; f.child_id=0; f.request_pending=0;
   f.phase=R3_STOP_RECORDED; f.attempts=0; f.failure_code=0; f.retry_after=0;
   return R3Save(f);
  }
double R3FirstLotsSince(const BasketFamilyState &f,double &first_price)
  {
   double total=0;ulong first=0;first_price=0;
#ifdef __MQL5__
   if(!HistorySelect(0,TimeCurrent()+1)) return -1;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      const ulong deal=HistoryDealGetTicket(i);
      const string comment=HistoryDealGetString(deal,DEAL_COMMENT);
      if(deal<=f.source_entry_cursor || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol
         || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=R3Magic()
         || HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN
         || HistoryDealGetInteger(deal,DEAL_TYPE)!=f.direction
         || !MultiCommentMatches(comment,f.source_id) || StringFind(comment,"Grid")>=0) continue;
      total+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      if(first==0 || deal<first) {first=deal;first_price=HistoryDealGetDouble(deal,DEAL_PRICE);}
     }
#else
   for(int pool=0;pool<2;pool++)
      for(int i=(pool==0?OrdersTotal():OrdersHistoryTotal())-1;i>=0;i--)
        {
         if(!OrderSelect(i,SELECT_BY_POS,pool==0?MODE_TRADES:MODE_HISTORY)
            || (ulong)OrderTicket()<=f.source_entry_cursor || OrderSymbol()!=Symbol()
            || OrderMagicNumber()!=InpMagicNumber || OrderType()!=f.direction
            || !MultiCommentMatches(OrderComment(),f.source_id) || StringFind(OrderComment(),"Grid")>=0) continue;
         total+=OrderLots();
         if(first==0 || (ulong)OrderTicket()<first) {first=(ulong)OrderTicket();first_price=OrderOpenPrice();}
        }
#endif
   return total;
  }
void R3RestoreSource(const BasketFamilyState &f)
  {
   if(f.phase!=R3_STOP_RECORDED && f.phase!=R3_PRIMARY_CONFIRMED) return;
   const int i=R3GroupIndex(f.source_id);if(i<0)return;
   if(g_multi_groups[i].stop_event_sequence>f.source_sequence)return;
   // The complete journal is authoritative over a partially saved source record.
   g_multi_groups[i].stop_event_sequence=f.source_sequence;
   g_multi_groups[i].dirty=true;
  }
bool BasketRenewalResumeStop(MultiGroupState &group)
  {
   if(group.basket_mode_at_start!=3)return true;
   const int n=R3FamilyIndex(group.basket_family_id);if(n<0)return true;
   BasketFamilyState f=g_basket_families[n];
   if(f.phase!=R3_STOP_RECORDED || f.source_id!=group.id
      || f.source_sequence!=group.stop_event_sequence) return true;
   double price=0;const double fresh=R3FirstLotsSince(f,price);if(fresh<0)return false;
   if(fresh<=R3Tolerance())
     {
      // Finish the recorded cleanup even if the quote has bounced since the stop.
      if(!MultiDeletePending(group.id) || !MultiClosePositions(group.id))return false;
     }
   if(group.cycle_index!=f.target_index || group.transition_target_lots>0 || fresh<=R3Tolerance())
     {
      group.cycle_index=f.target_index;group.reversal_count=f.old_reversals+1;
      group.cumulative_loss_lots=f.target_loss;group.previous_grid_lots=f.grid_before;
      group.pending_index=-1;
#ifdef __MQL5__
      group.pending_ticket=0;group.grid_pending_ticket=0;group.favorable_grid_pending_ticket=0;
#else
      group.pending_ticket=-1;group.grid_pending_ticket=-1;group.favorable_grid_pending_ticket=-1;
#endif
      group.anchor_price=price;group.last_entry=price;group.linear_extreme=price;
      group.first_lots=fresh;group.total_lots=fresh;
      group.grid_lots=group.previous_grid_lots>0
#ifdef __MQL5__
         ? VolumeNormalize(group.previous_grid_lots*g_gui_applied_config.grid_lot_multiplier)
#else
         ? VolumeNormalize(group.previous_grid_lots*InpGridLotMultiplier)
#endif
         : fresh;
      group.transition_target_lots=fresh+R3Tolerance()>=f.target_lots ? 0 : f.target_lots;
      group.grid_filled_mask=0;group.grid_filled_levels=0;group.grid_pending_level=0;group.grid_pending_price=0;
      group.favorable_grid_filled_mask=0;group.favorable_grid_filled_levels=0;
      group.favorable_grid_pending_level=0;group.favorable_grid_pending_price=0;
      BasketRenewalSaveTransition(group);
     }
   return true;
  }
void BasketRenewalSaveTransition(MultiGroupState &group)
  {
   if(group.basket_mode_at_start!=3) return;
   group.dirty=true; MultiSaveGroup(group); GlobalVariablesFlush();
  }
bool BasketRenewalOpenMarket(MultiGroupState &group,const R3_DIRECTION type,const double lots)
  {
#ifndef __MQL5__
#ifndef NMR_RENEWAL_CORE
   if(group.basket_mode_at_start==3)
     {
      group.launch_attempted=true;group.dirty=true;MultiSaveGroup(group);GlobalVariablesFlush();
      g_multi_last_send_error=0;
      const bool sent=MultiOpenMarket(group,type,lots);
      if(g_reset_pending) return false;
      if(!sent) MultiRecordLaunchFailure(group,g_multi_last_send_error);
      else {group.launch_attempted=false;group.dirty=true;MultiSaveGroup(group);}
      return sent;
     }
#endif
#endif
   return MultiOpenMarket(group,type,lots);
  }
void R3LogFirst(const BasketFamilyState &f,const MultiGroupState &group,const string role)
  {
#ifdef __MQL5__
   for(int p=0;p<PositionsTotal();p++)
     {
      const ulong position=PositionGetTicket(p);
      if(!MultiIsOurPosition(position,group.id) || StringFind(PositionGetString(POSITION_COMMENT),"Grid")>=0)continue;
      const ulong identifier=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      const double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      if(!HistorySelectByPosition(identifier))continue;
      for(int i=0;i<HistoryDealsTotal();i++)
        {
         const ulong deal=HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN)continue;
         PrintFormat("[R3_FIRST][F=%d][GEN=%d][SOURCE=%d][SEQ=%d][ROLE=%s][GROUP=%d][DEAL=%I64u][DIR=%d][VOLUME=%.8f][SL=%.8f][TP=%.8f][CYCLE=%d][REV=%d][LOSS=%.8f]",
            f.id,f.generation,f.source_id,f.source_sequence,role,group.id,deal,
            (int)HistoryDealGetInteger(deal,DEAL_TYPE),HistoryDealGetDouble(deal,DEAL_VOLUME),
            sl,tp,group.cycle_index,group.reversal_count,group.cumulative_loss_lots);
        }
     }
#else
   for(int i=0;i<OrdersTotal();i++)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderSymbol()==Symbol()
         && OrderMagicNumber()==InpMagicNumber && OrderType()<=OP_SELL
         && MultiCommentMatches(OrderComment(),group.id) && StringFind(OrderComment(),"Grid")<0)
         PrintFormat("[R3_FIRST][F=%d][GEN=%d][SOURCE=%d][SEQ=%d][ROLE=%s][GROUP=%d][DEAL=%d][DIR=%d][VOLUME=%.8f][SL=%.8f][TP=%.8f][CYCLE=%d][REV=%d][LOSS=%.8f]",
            f.id,f.generation,f.source_id,f.source_sequence,role,group.id,OrderTicket(),OrderType(),OrderLots(),
            OrderStopLoss(),OrderTakeProfit(),group.cycle_index,group.reversal_count,group.cumulative_loss_lots);
#endif
  }
bool BasketRenewalConfirmFirstOrder(MultiGroupState &group,const int direction,const double first_lots)
  {
   if(group.basket_mode_at_start!=3) return true;
   const int n=R3FamilyIndex(group.basket_family_id); if(n<0) return false;
   BasketFamilyState f=g_basket_families[n];
   if(f.source_id!=group.id || f.source_sequence!=group.stop_event_sequence || f.phase!=R3_STOP_RECORDED) return true;
   if(f.source_id!=group.id || f.source_sequence!=group.stop_event_sequence
      || f.phase!=R3_STOP_RECORDED || group.cycle_index!=f.target_index
      || direction!=f.direction || MathAbs(first_lots-f.target_lots)>R3Tolerance()
      || group.transition_target_lots>0 || R3HasOpeningOrder(group.id)
      || !MultiStopsVerified(group,(R3_DIRECTION)direction)) return false;
   f.confirmed_lots=first_lots; f.phase=R3_PRIMARY_CONFIRMED;
   BasketRenewalSaveTransition(group);
   if(!R3Save(f))return false;
   R3LogFirst(f,group,"SOURCE");return true;
  }
bool BasketRenewalManagesChild(const MultiGroupState &group)
  {
   if(group.basket_mode_at_start!=3) return false;
   const int n=R3FamilyIndex(group.basket_family_id); if(n<0) return false;
   BasketFamilyState f=g_basket_families[n];
   return f.child_id==group.id && (f.request_pending || f.phase==R3_CHILD_RESERVED
      || f.phase==R3_CHILD_IN_FLIGHT || f.phase==R3_CHILD_PARTIAL || f.phase==R3_CANCELED
      || f.phase==R3_FAILED);
  }
bool BasketRenewalProtectOnly(MultiGroupState &group)
  {
   if(group.basket_mode_at_start!=3) return false;
   if(!g_basket_renewal_storage_fault && R3FamilyIndex(group.basket_family_id)>=0) return false;
   R3_TICKET t=0;R3_DIRECTION d=0;double v=0,e=0,sl=0,tp=0;
   if(R3Position(group.id,t,d,v,e,sl,tp)) MultiSetStops(group,d);
   return true;
  }
bool BasketRenewalFlatTakeProfit(const MultiGroupState &group)
  {
#ifdef __MQL5__
   return false; // MT5 already has its group-scoped broker-TP reconciliation.
#else
   if(group.anchor_price<=0 || group.take_profit_points<=0) return false;
   const int type=MultiSequenceDirection(group,group.cycle_index);
   const double target=MultiTakeProfitPrice(group,type);
   RefreshRates();
   if((type==OP_BUY && Bid>=target) || (type==OP_SELL && Ask<=target)) return true;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) || OrderSymbol()!=Symbol()
         || OrderMagicNumber()!=InpMagicNumber || OrderType()!=type
         || !MultiCommentMatches(OrderComment(),group.id)) continue;
      if(OrderTakeProfit()>0 && MathAbs(OrderClosePrice()-OrderTakeProfit())<=Point*2)
         return true;
      return false;
     }
   return false;
#endif
  }
void R3InitializeChild(MultiGroupState &child,const R3_DIRECTION type,const double lots,const double entry)
  {
   if(child.anchor_price<=0) child.anchor_price=entry;
   child.last_entry=entry; child.linear_extreme=entry;
   child.first_lots=lots; child.total_lots=lots; child.grid_lots=lots;
   child.dirty=true;
  }
bool BasketRenewalAdoptInitial(MultiGroupState &group,const bool allow_send=false)
  {
#ifdef __MQL5__
   if(group.basket_mode_at_start!=3 || (group.pair_role!=1 && group.pair_role!=2
      && group.pair_role!=4 && group.pair_role!=5))return false;
   const int peer=R3GroupIndex(group.pair_peer_id);
   const bool peer_ended=peer<0 || !g_multi_groups[peer].active;
   R3_TICKET ticket=0;R3_DIRECTION type=0;double volume=0,entry=0,sl=0,tp=0;
   const bool live=R3Position(group.id,ticket,type,volume,entry,sl,tp);
   BasketRenewalReconcileRequest(group);
   if(!live)
     {
      if(!peer_ended)return false;
      if(R3HasPending(group.id) && !R3CancelOutstandingOrders(group.id))return true;
      BasketRenewalReconcileRequest(group);
      if(R3RequestUnknown(group))return true;
      // A filled initial order can also have closed before its callback. Keep
      // its actual first entry for the existing broker TP/SL reconciliation.
      BasketFamilyState first;ZeroMemory(first);first.source_id=group.id;
      first.direction=group.first_direction==FIRST_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      volume=R3FirstLotsSince(first,entry);
      if(volume<0)return true;
      if(volume<=R3Tolerance())
        {group.active=false;group.dirty=true;MultiSaveGroup(group);return true;}
      type=(R3_DIRECTION)first.direction;
     }
   const double target=group.transition_target_lots>0?group.transition_target_lots:group.initial_pending_lots;
   R3InitializeChild(group,type,volume,entry);
   if(live && (!MultiSetStops(group,type) || !MultiStopsVerified(group,type)))
     {MultiSaveGroup(group);return true;}
   if(group.pair_role==4 || group.pair_role==5)
     {
      if(peer>=0)
        {
         const ulong peer_ticket=g_multi_groups[peer].initial_high_ticket>0
            ?g_multi_groups[peer].initial_high_ticket:g_multi_groups[peer].initial_low_ticket;
         if(peer_ticket>0 && MultiInitialPendingStatus(peer_ticket,g_multi_groups[peer].id)==REVERSE_PENDING_ACTIVE
            && !DeletePendingTicket(peer_ticket,"Mode3 initial fill sibling delete"))
           {MultiSaveGroup(group);return true;}
        }
     }
   if(R3HasOpeningOrder(group.id))
     {
      if(!peer_ended || !R3CancelOutstandingOrders(group.id))
        {MultiSaveGroup(group);return true;}
     }
   if(R3RequestUnknown(group)) {MultiSaveGroup(group);return true;}
   // A live peer still requires the whole requested initial amount. A late
   // partial after that peer ended is adopted as received without replacement.
   if(live && !peer_ended && volume+R3Tolerance()<target)
     {
      if(!allow_send) {MultiSaveGroup(group);return true;}
      R3_TICKET pt=0;R3_DIRECTION pd=0;double pv=0,pe=0,psl=0,ptp=0;
      if(g_multi_groups[peer].request_in_flight
         || !R3Position(g_multi_groups[peer].id,pt,pd,pv,pe,psl,ptp)
         || !MultiStopsVerified(g_multi_groups[peer],pd))
        {MultiSaveGroup(group);return true;}
      const double volume_before=volume;
      const bool completed=R3_OPEN_INITIAL_REMAINDER(group,type,target);
      const int send_error=R3_EXECUTION_ERROR();
      if(g_reset_pending)return true;
      if(!R3Position(group.id,ticket,type,volume,entry,sl,tp))return true;
      R3InitializeChild(group,type,volume,entry);
      if(!MultiSetStops(group,type) || !MultiStopsVerified(group,type))
        {MultiSaveGroup(group);return true;}
      if(!completed)
        {
         const bool progressed=volume>volume_before+R3Tolerance();
         const bool rejected=send_error!=10009 && send_error!=10010 && send_error!=10008;
         // A confirmed partial receipt retains its original target and peer.
         // A definite rejection adopts the protected actual amount only.
         if(!progressed && rejected && !R3RequestUnknown(group))
           {group.pair_role=3;group.pair_failure_retcode=send_error;
            group.initial_high_ticket=0;group.initial_low_ticket=0;group.signal_consumed=true;
            group.transition_target_lots=0;group.state=STATE_RECOVERY;}
         MultiSaveGroup(group);return true;
        }
      if(R3HasOpeningOrder(group.id) || R3RequestUnknown(group)
         || volume+R3Tolerance()<target)
        {MultiSaveGroup(group);return true;}
     }
   group.pair_role=0;group.pair_peer_id=0;
   group.signal_consumed=true;
   group.initial_high_ticket=0;group.initial_low_ticket=0;
   group.transition_target_lots=0;
   MultiSaveGroup(group);
   // Publish historical adoption before the next batch snapshots started_mask.
   return true;
#else
   return false;
#endif
  }
void BasketRenewalProtectVisible()
  {
   if(g_reset_pending)return;
   for(int i=0;i<ArraySize(g_multi_groups);i++)
     {
      MultiGroupState group=g_multi_groups[i];
      if(group.basket_mode_at_start!=3 || !group.active)continue;
      if(BasketRenewalAdoptInitial(group))
        {g_multi_groups[i]=group;continue;}
      const int n=R3FamilyIndex(group.basket_family_id);if(n<0)continue;
      BasketFamilyState f=g_basket_families[n];
      if(f.child_id!=group.id || f.phase==R3_PAIRED)continue;
      R3_TICKET t=0;R3_DIRECTION d=0;double v=0,e=0,sl=0,tp=0;
      if(!R3Position(group.id,t,d,v,e,sl,tp))continue;
      R3InitializeChild(group,d,v,e);
      MultiSetStops(group,d);
      BasketRenewalReconcileRequest(group);
      g_multi_groups[i]=group;MultiSaveGroup(g_multi_groups[i]);
     }
  }
void R3BindChild(BasketFamilyState &f,const bool paired)
  {
   const int child_id=f.child_id;
   const int child=R3GroupIndex(f.child_id);
   if(paired && child>=0) R3LogFirst(f,g_multi_groups[child],"CHILD");
   f.first_id=f.source_id; f.second_id=f.child_id;
   f.first_finished=R3GroupIndex(f.source_id)<0 ? 1 : 0; f.second_finished=0;
   f.started_mask=3; f.generation++;
   f.phase=paired ? R3_PAIRED : R3_CANCELED;
   if(!paired)f.child_id=0;
   if(!R3Save(f))return;
   PrintFormat("[R3_BIND][F=%d][GEN=%d][SOURCE=%d][SEQ=%d][CHILD=%d][DIR=%d][LOTS=%.8f][PAIRED=%d][PEER_FINISHED=%d]",
               f.id,f.generation,f.source_id,f.source_sequence,child_id,1-f.direction,f.confirmed_lots,paired?1:0,f.peer_finished);
  }
void BasketRenewalProcess()
  {
   if(g_reset_pending || g_basket_renewal_storage_fault) return;
   for(int n=0;n<ArraySize(g_basket_families);n++)
     {
      BasketFamilyState f=g_basket_families[n];
      if(f.phase==R3_IDLE)
        {
#ifndef __MQL5__
         const int first=R3GroupIndex(f.first_id);
         if(first>=0 && g_multi_groups[first].launch_failed)
            BasketRenewalInitialFailure(f.first_id,f.second_id);
#endif
        }
      if(f.phase==R3_IDLE || f.phase==R3_NO_RENEWAL || f.phase==R3_PAIRED
         || (f.phase==R3_FAILED && f.child_id==0) || (f.phase==R3_CANCELED && f.child_id==0)) continue;
      int si=R3GroupIndex(f.source_id), ci=R3GroupIndex(f.child_id);
      R3_TICKET st=0; R3_DIRECTION sd=0; double sv=0,se=0,ssl=0,stp=0;
      const bool source_live=si>=0 && g_multi_groups[si].active
         && g_multi_groups[si].stop_event_sequence==f.source_sequence
         && g_multi_groups[si].cycle_index==f.target_index
         && R3Position(f.source_id,st,sd,sv,se,ssl,stp) && (int)sd==f.direction;
      if(f.phase==R3_STOP_RECORDED)
        {
         if(si<0) {f.phase=R3_NO_RENEWAL;R3Save(f);}
         else BasketRenewalConfirmFirstOrder(g_multi_groups[si],(int)sd,g_multi_groups[si].first_lots);
         continue;
        }
      if(f.phase==R3_PRIMARY_CONFIRMED && (!f.peer_finished || f.started_mask!=3))
        {
         f.phase=R3_NO_RENEWAL;R3Save(f);
         PrintFormat("[R3_NO_RENEWAL][F=%d][GEN=%d][SOURCE=%d][SEQ=%d]",f.id,f.generation,f.source_id,f.source_sequence);
         continue;
        }
      if(!source_live) f.phase=R3_CANCELED;
      if(f.phase==R3_CANCELED && f.child_id==0) {R3Save(f);continue;}
      if(f.child_id==0)
        {
         if(g_multi_next_id>=2147483646) {f.phase=R3_FAILED;R3Save(f);continue;}
         f.child_id=g_multi_next_id++; f.phase=R3_CHILD_RESERVED;
         if(!R3Save(f)) return;
        }
      ci=R3GroupIndex(f.child_id);
      if(ci<0)
        {
         MultiGroupState child; MultiResetState(child,f.child_id);
         child.basket_mode_at_start=3; child.basket_family_id=f.id;
         child.first_direction=f.direction==0 ? FIRST_SELL : FIRST_BUY;
         child.cycle_mode=f.cycle_mode; child.stop_points=f.stop_points;
         child.take_profit_points=f.take_profit_points;
         child.transition_target_lots=f.confirmed_lots;
#ifdef __MQL5__
         child.dual_basket_member=true;
#else
         child.launch_confirmed=true;
#endif
         ci=ArraySize(g_multi_groups);
         if(ArrayResize(g_multi_groups,ci+1)!=ci+1) return;
         g_multi_groups[ci]=child; MultiSaveGroup(g_multi_groups[ci]);
        }
      MultiGroupState child=g_multi_groups[ci];
      R3_TICKET ct=0; R3_DIRECTION cd=0; double cv=0,ce=0,csl=0,ctp=0;
      bool child_live=R3Position(f.child_id,ct,cd,cv,ce,csl,ctp);
      if(child_live)
        {
         R3InitializeChild(child,cd,cv,ce);
         if(!MultiSetStops(child,cd) || !MultiStopsVerified(child,cd))
           {g_multi_groups[ci]=child;MultiSaveGroup(g_multi_groups[ci]);continue;}
        }
      if(f.phase!=R3_CANCELED && !child_live && child.first_lots>R3Tolerance())
        {
         // Record the closed first exposure before waiting on another active
         // order; that remainder can still arrive and must not revive it.
         f.phase=R3_CANCELED;if(!R3Save(f))return;
        }
      if(R3HasPending(child.id))
        {
         // An accepted partial request may still fill its outstanding remainder.
         // Do not bind or supplement it until that order is terminal.
         if(f.phase==R3_CANCELED || f.phase==R3_FAILED || cv+R3Tolerance()>=f.confirmed_lots)
            R3CancelOutstandingOrders(child.id);
         g_multi_groups[ci]=child;MultiSaveGroup(g_multi_groups[ci]);
         if(!R3Save(f))return;
         continue;
        }
      BasketRenewalReconcileRequest(child);
      if(f.request_pending)
        {
         if(!R3RequestUnknown(child) && (cv>f.volume_before+R3Tolerance() || R3NewEntryAfterRequest(child)))
           {f.request_pending=0;R3Save(f);}
         else if(!child_live && !R3HasPending(child.id) && R3NewEntryAfterRequest(child))
           {
            R3ClearRequest(child);f.request_pending=0;f.phase=R3_CANCELED;
            f.first_id=f.source_id;f.second_id=f.child_id;
            f.first_finished=source_live?0:1;f.second_finished=1;f.started_mask=3;
            R3Save(f);
           }
         else if(!R3HasDurableAttempt(child))
           {f.request_pending=0;R3Save(f);}
         else continue;
        }
      // An accepted partial first order that has already closed ends this
      // opening intent. Its old fills must never be replaced from zero.
      if(!child_live && !f.request_pending && child.first_lots>R3Tolerance()
         && !R3HasPending(child.id) && !R3RequestUnknown(child))
        {
         f.phase=R3_CANCELED;
         f.first_id=f.source_id;f.second_id=f.child_id;
         f.first_finished=source_live?0:1;f.second_finished=1;f.started_mask=3;
         if(!R3Save(f))return;
        }
      if(f.phase==R3_CANCELED || f.phase==R3_FAILED)
        {
         child.transition_target_lots=0; child.dirty=true;
         if(child_live) {g_multi_groups[ci]=child;MultiSaveGroup(g_multi_groups[ci]);R3BindChild(f,false);}
         else {child.active=false;g_multi_groups[ci]=child;MultiSaveGroup(g_multi_groups[ci]);f.child_id=0;R3Save(f);}
         continue;
        }
      if(child_live && ((int)cd!=1-f.direction || cv>f.confirmed_lots+R3Tolerance()))
        {f.phase=R3_FAILED;f.failure_code=-3;R3Save(f);continue;}
      if(child_live && MathAbs(cv-f.confirmed_lots)<=R3Tolerance())
        {
         child.transition_target_lots=0; child.dirty=true;
         g_multi_groups[ci]=child;MultiSaveGroup(g_multi_groups[ci]);R3BindChild(f,true);continue;
        }
      g_multi_groups[ci]=child;MultiSaveGroup(g_multi_groups[ci]);
      if(R3RequestUnknown(child) || TimeCurrent()<f.retry_after) continue;
      if(si<0 || !MultiStopsVerified(g_multi_groups[si],sd)) continue;
      ReversalLotPlan plan;
      if(!BuildReversalLotPlan(f.confirmed_lots,plan) || plan.status==REVERSAL_LOT_RESTART_GROUP)
        {f.phase=R3_FAILED;f.failure_code=-4;R3Save(f);continue;}
      const double volume=MathMin(plan.first_lots,f.confirmed_lots-cv);
      if(!R3PrepareNextLeg(child))return;
      f.volume_before=cv;f.request_pending=1;f.phase=child_live?R3_CHILD_PARTIAL:R3_CHILD_IN_FLIGHT;
      f.attempts++;
      if(!R3Save(f)) return;
#ifndef __MQL5__
#ifndef NMR_RENEWAL_CORE
      child.launch_attempted=true;child.dirty=true;MultiSaveGroup(child);GlobalVariablesFlush();
#endif
#endif
      const bool sent=R3_SEND_MARKET_LEG(child,(R3_DIRECTION)(1-f.direction),volume);
      if(g_reset_pending || n>=ArraySize(g_basket_families)) return;
      ci=R3GroupIndex(f.child_id); if(ci<0) return;
      g_multi_groups[ci]=child;g_multi_groups[ci].dirty=true;MultiSaveGroup(g_multi_groups[ci]);
      // Synchronous fills must receive protection in this call, before another tick.
      if(R3Position(f.child_id,ct,cd,cv,ce,csl,ctp))
        {
         R3InitializeChild(child,cd,cv,ce);
         const bool protected_now=MultiSetStops(child,cd) && MultiStopsVerified(child,cd);
#ifndef __MQL5__
#ifndef NMR_RENEWAL_CORE
         if(sent) child.launch_attempted=false;
#endif
#endif
         if(cv>f.volume_before+R3Tolerance() && !R3RequestUnknown(child) && !R3HasPending(child.id)) f.request_pending=0;
         g_multi_groups[ci]=child;g_multi_groups[ci].dirty=true;MultiSaveGroup(g_multi_groups[ci]);
         if(protected_now && (int)cd==1-f.direction
            && MathAbs(cv-f.confirmed_lots)<=R3Tolerance() && !f.request_pending)
           {
            g_multi_groups[ci].transition_target_lots=0;
            g_multi_groups[ci].dirty=true;MultiSaveGroup(g_multi_groups[ci]);
            R3BindChild(f,true);continue;
           }
         R3Save(f);
        }
      int error=0;
#ifdef __MQL5__
      error=R3_EXECUTION_ERROR();
      const bool ambiguous=error==10012 || error==10031 || child.request_in_flight;
      const bool permanent=error==10014 || error==10013 || error==10017 || error==10035;
#else
      error=R3_EXECUTION_ERROR();
      const bool ambiguous=error==128 || error==6 || error==0;
      const bool permanent=error==131 || error==3 || error==7 || error==64;
#endif
      if(!sent && !ambiguous)
        {
         f.request_pending=0;f.failure_code=error;
         R3ClearRequest(g_multi_groups[ci]);MultiSaveGroup(g_multi_groups[ci]);
         f.retry_after=TimeCurrent()+(int)MathMin(300,5*MathPow(2,MathMin(f.attempts-1,6)));
         if(permanent) f.phase=R3_FAILED;
         R3Save(f);
        }
      PrintFormat("[R3_REQUEST][F=%d][GEN=%d][SOURCE=%d][SEQ=%d][CHILD=%d][DIR=%d][VOLUME=%.8f][TARGET=%.8f][CODE=%d]",
                  f.id,f.generation,f.source_id,f.source_sequence,f.child_id,1-f.direction,volume,f.confirmed_lots,error);
     }
  }
void BasketRenewalCancelAll()
  {
   g_basket_next_id_floor=(int)MathMax(g_basket_next_id_floor,g_multi_next_id);
   if(ArraySize(g_basket_families)>0) R3Put(R3Prefix()+".next",g_basket_next_id_floor);
   for(int i=0;i<ArraySize(g_basket_families);i++)
     {
      BasketFamilyState f=g_basket_families[i];
      f.phase=R3_CANCELED;f.child_id=0;f.request_pending=0;
      f.first_finished=1;f.second_finished=1;R3Save(f);
     }
   ArrayResize(g_basket_families,0);
   GlobalVariableDel(R3Prefix()+".cfgok");
   const string cfg=R3Prefix()+".cfg";
   GlobalVariableDel(cfg+".owner.profile");GlobalVariableDel(cfg+".owner.schema");
   GlobalVariableDel(cfg+".configfingerprint");GlobalVariableDel(cfg+".configfingerprint2");
   GlobalVariablesFlush();
  }

#undef R3_TICKET
#undef R3_DIRECTION
