package utility;

import gnu.trove.TIntArrayList;

public class StringUtil {
        public static final String NewLineString = System.getProperty("line.separator"); //$NON-NLS-1$
        public static int findAll(int[] poss, String str, int target) {
                if (poss.length == 0) {
                        return 0;
                }
                
                int i = 0;
                int count = 0;
                while (i < str.length()) {
                        int p = str.indexOf(target, i);
                        if (p < 0) {
                                for (int c = count; c < poss.length; ++c) {
                                        poss[c] = -1;
                                }
                                return count;
                        }
                        poss[count] = p;
                        ++count;
                        i = p + 1;
                }
                return count;
        }
        public static String[] split(String str, int sepChar) {
                TIntArrayList sepPoss = new TIntArrayList();
                int pos = 0;
                while (pos < str.length()) {
                        int q = str.indexOf(sepChar, pos);
                        if (q != -1) {
                                sepPoss.add(q);
                                pos = q + 1;
                        }
                        else {
                                sepPoss.add(str.length());
                                pos = str.length();
                        }
                }
                int[] poss = sepPoss.toNativeArray();
                String[] substrings = new String[poss.length];
                if (poss.length >= 1) {
                        int i = 0;
                        substrings[i] = str.substring(0, poss[0]);
                        ++i;
                        for (; i < poss.length; ++i) {
                                substrings[i] = str.substring(poss[i - 1] + 1, poss[i]);
                        }
                }
                return substrings;
        }
        
        public static String join(String[] ary, String with) {
                StringBuffer buf = new StringBuffer();
                for (int i = 0; i < ary.length; ++i) {
                        if (i > 0) {
                                buf.append(with);
                        }
                        buf.append(ary[i]);
                }
                return buf.toString();
        }
        
        public static String join(String[] ary, int begin, int end, String with) {
                if (begin < 0) {
                        begin = 0;
                }
                if (end > ary.length) {
                        end = ary.length;
                }
                StringBuffer buf = new StringBuffer();
                for (int i = begin; i < end; ++i) {
                        if (i > begin) {
                                buf.append(with);
                        }
                        buf.append(ary[i]);
                }
                return buf.toString();
        }
        
        public static String replaceFirst(String str, String pat, String replacement) {
                int pos = str.indexOf(pat);
                if (pos >= 0) {
                        return str.substring(0, pos) + replacement + str.substring(pos + pat.length());
                } else {
                        return str;
                }
        }
        
//      public static Double[] scanDoubleValues(String str, int sepChar) {
//              String[] subs = StringUtil.split(str, sepChar);
//              Double[] values = new Double[subs.length];
//              for (int i = 0; i < subs.length; ++i) {
//                      try {
//                              double v = Double.parseDouble(subs[i]);
//                              values[i] = v;
//                      } catch (NumberFormatException e) {
//                              values[i] = null;
//                      }
//              }
//              return values;
//      }
}
